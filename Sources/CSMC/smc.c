#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <poll.h>
#include <fcntl.h>
#include <float.h>
#include <mach/mach_time.h>

/* AppleSMC user-client ABI. All calls are serialized by the caller. */
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } PLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; PLimit limit; KeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} Packet;
_Static_assert(sizeof(Packet) == 80, "Unexpected AppleSMC ABI layout");
static io_connect_t connection = 0;
static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0]<<24) | ((uint32_t)(uint8_t)s[1]<<16)
        | ((uint32_t)(uint8_t)s[2]<<8) | (uint8_t)s[3];
}
static void fourstr(uint32_t n, char *out) {
    for (int i=0; i<4; i++) out[i]=(char)(n >> (24-i*8)); out[4]=0;
}
static int call(Packet *input, Packet *output) {
    if (!connection && bf_open()) return -1;
    memset(output, 0, sizeof(*output)); size_t n=sizeof(*output);
    kern_return_t rc=IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &n);
    return rc==KERN_SUCCESS && output->result==0 && n==sizeof(*output) ? 0 : -1;
}
int bf_intel_hardware(void) {
#if !defined(__x86_64__)
    return 0;
#else
    int translated=0,arm=0; size_t size=sizeof(int);
    if(!sysctlbyname("sysctl.proc_translated",&translated,&size,NULL,0) && translated==1) return 0;
    size=sizeof(int);
    if(!sysctlbyname("hw.optional.arm64",&arm,&size,NULL,0) && arm==1) return 0;
    return 1;
#endif
}
int bf_open(void) {
    if(!bf_intel_hardware()) return -1;
    if (connection) return 0;
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t rc=IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service); if(rc!=KERN_SUCCESS) { connection=0; return -1; } return 0;
}
void bf_close(void) { if(connection) IOServiceClose(connection); connection=0; }
static int info(const char *key, KeyInfo *result) {
    if(!key || strlen(key)!=4) return -1;
    Packet in={0}, out={0}; in.key=fourcc(key); in.command=9;
    if(call(&in,&out) || out.info.dataSize>32 || !out.info.dataSize) return -1;
    *result=out.info; return 0;
}
int bf_read(const char *key, BFValue *value) {
    KeyInfo ki; if(!value || info(key,&ki)) return -1;
    Packet in={0}, out={0}; in.key=fourcc(key); in.command=5; in.info.dataSize=ki.dataSize;
    if(call(&in,&out)) return -1;
    memset(value,0,sizeof(*value)); memcpy(value->key,key,4);
    fourstr(ki.dataType,value->type); value->size=ki.dataSize;
    memcpy(value->bytes,out.bytes,ki.dataSize); return 0;
}
static int write_raw(const char *key, const uint8_t *bytes, size_t count) {
    if(geteuid()!=0) return -1;
    KeyInfo ki; if(info(key,&ki) || count!=ki.dataSize || count>32) return -1;
    Packet in={0}, out={0}; in.key=fourcc(key); in.command=6; in.info.dataSize=(uint32_t)count;
    memcpy(in.bytes,bytes,count); return call(&in,&out);
}
int bf_key_at(uint32_t index, char key[5]) {
    if (!key) return -1;
    Packet in={0}, out={0}; in.command=8; in.index=index;
    if(call(&in,&out)) return -1; fourstr(out.key,key); return 0;
}
int bf_number(const char *key, double *number) {
    BFValue v; if(!number || bf_read(key,&v)) return -1;
    if(!strcmp(v.type,"sp78") && v.size==2) {
        int16_t raw=(int16_t)(((uint16_t)v.bytes[0]<<8)|v.bytes[1]); *number=raw/256.0;
    } else if(!strcmp(v.type,"fpe2") && v.size==2) {
        *number=(((uint16_t)v.bytes[0]<<8)|v.bytes[1])/4.0;
    } else if(!strcmp(v.type,"flt ") && v.size==4) {
        float f; memcpy(&f,v.bytes,4); *number=f;
    } else if((!strcmp(v.type,"ui8 ") && v.size==1)
           || (!strcmp(v.type,"ui16") && v.size==2)
           || (!strcmp(v.type,"ui32") && v.size==4)) {
        uint32_t raw=0; for(uint32_t i=0;i<v.size;i++) raw=(raw<<8)|v.bytes[i]; *number=raw;
    } else return -1;
    return isfinite(*number)?0:-1;
}
int bf_fan_count(void) {
    double n; if(bf_number("FNum",&n) || n<0 || n>10 || floor(n)!=n) return -1; return (int)n;
}
int bf_fan_bounds(int fan, double *minimum, double *maximum) {
    if(fan<0 || fan>=10 || !minimum || !maximum) return -1;
    char key[5]; snprintf(key,5,"F%dMn",fan); if(bf_number(key,minimum)) return -1;
    snprintf(key,5,"F%dMx",fan); if(bf_number(key,maximum)) return -1;
    return bf_valid_target(*minimum,*minimum,*maximum)?0:-1;
}
static int set_number(const char *key, double n) {
    BFValue v; if(!isfinite(n) || bf_read(key,&v)) return -1;
    uint8_t b[4]={0};
    if(!strcmp(v.type,"fpe2") && v.size==2 && n>=0 && n<=16383.75) {
        uint16_t raw=(uint16_t)lround(n*4); b[0]=raw>>8; b[1]=raw&255;
    } else if(!strcmp(v.type,"flt ") && v.size==4 && fabs(n)<=FLT_MAX) { float f=(float)n; memcpy(b,&f,4);
    } else if(!strcmp(v.type,"ui8 ") && v.size==1 && n>=0 && n<=255) b[0]=(uint8_t)n;
    else if(!strcmp(v.type,"ui16") && v.size==2 && n>=0 && n<=65535) {
        uint16_t raw=(uint16_t)n; b[0]=raw>>8; b[1]=raw&255;
    } else return -1;
    return write_raw(key,b,v.size);
}
static int set_mode(int fan, int manual) {
    char mode[5]; snprintf(mode,5,"F%dMd",fan); BFValue perFan, legacy;
    int hasPerFan=!bf_read(mode,&perFan) && !strcmp(perFan.type,"ui8 ") && perFan.size==1;
    int hasLegacy=!bf_read("FS! ",&legacy) && !strcmp(legacy.type,"ui16") && legacy.size==2;
    if(!hasPerFan && !hasLegacy) return -1;
    int error=0;
    if(hasPerFan && set_number(mode,manual?1:0)) error=1;
    /* Intel machines may expose both registers. Do not skip FS! merely
       because F#Md exists: the global force bit gates manual control. */
    if(hasLegacy) {
        uint16_t bits=((uint16_t)legacy.bytes[0]<<8)|legacy.bytes[1];
        bits=bf_mode_bits(bits,fan,manual);
        uint8_t bytes[2]={(uint8_t)(bits>>8),(uint8_t)bits};
        if(write_raw("FS! ",bytes,2)) error=1;
    }
    return error?-1:0;
}
int bf_can_control(int fan) {
    char key[5]; double lo,hi; BFValue target,mode;
    if(bf_fan_bounds(fan,&lo,&hi)) return 0;
    snprintf(key,5,"F%dTg",fan);
    if(bf_read(key,&target) || (!(!strcmp(target.type,"fpe2") && target.size==2 && hi<=16383.75) && !(!strcmp(target.type,"flt ") && target.size==4))) return 0;
    snprintf(key,5,"F%dMd",fan);
    if(!bf_read(key,&mode) && !strcmp(mode.type,"ui8 ") && mode.size==1) return 1;
    return !bf_read("FS! ",&mode) && !strcmp(mode.type,"ui16") && mode.size==2;
}
int bf_fan_mode(int fan) {
    if(fan<0 || fan>=10) return -1;
    BFValue v;
    if(!bf_read("FS! ",&v) && !strcmp(v.type,"ui16") && v.size==2) {
        unsigned bits=((unsigned)v.bytes[0]<<8)|v.bytes[1];
        return !!(bits&(1u<<fan));
    }
    char key[5]; snprintf(key,5,"F%dMd",fan); double value;
    if(bf_number(key,&value) || (value!=0 && value!=1)) return -1;
    return (int)value;
}
static int verify_mode(int fan, int manual) {
    for(int attempt=0;attempt<11;attempt++) {
        if(bf_fan_mode(fan)==!!manual) return 0;
        if(attempt<10) usleep(10000);
    }
    return -1;
}

int bf_fan_auto(int fan) {
    if(fan<0 || fan>=bf_fan_count() || set_mode(fan,0)) return -1;
    return verify_mode(fan,0);
}
int bf_fan_set(int fan, double rpm) {
    double lo,hi; if(!bf_can_control(fan) || bf_fan_bounds(fan,&lo,&hi) || !bf_valid_target(rpm,lo,hi)) return -1;
    char key[5]; snprintf(key,5,"F%dTg",fan);
    if(set_number(key,rpm)) return -10;
    if(set_mode(fan,1)) return -11;
    if(set_number(key,rpm)) return -12;
    if(verify_mode(fan,1)) return -13;
    double actual; snprintf(key,5,"F%dTg",fan);
    for(int attempt=0;attempt<11;attempt++) {
        if(!bf_number(key,&actual) && fabs(actual-rpm)<=1.0) return 0;
        if(attempt<10) usleep(10000);
    }
    return -14;
}
int bf_restore_all(void) {
    int n=bf_fan_count(), errors=0; if(n<0) return -1;
    for(int i=0;i<n;i++) if(bf_fan_auto(i)) errors++;
    return errors ? -1 : 0;
}
static double monotime(void) {
    mach_timebase_info_data_t scale; mach_timebase_info(&scale);
    return (double)mach_continuous_time()*scale.numer/scale.denom/1e9;
}
static int ready(int fd, short events, double deadline) {
    while(1) {
        double remaining=deadline-monotime(); if(remaining<=0) return -1;
        struct pollfd p={.fd=fd,.events=events};
        int rc=poll(&p,1,(int)ceil(remaining*1000));
        if(rc<0 && errno==EINTR) continue;
        return rc>0 && (p.revents&events)?0:-1;
    }
}
// 10 fans: up to 2 s verification, plus two 1 s rollback passes on error.
// Leave 1.5 s for dispatch/IO. This client deadline never renews the lease.
double bf_request_timeout(const char *command) {
    if(command && !strncmp(command,"APPLY ",6)) return 5.5;
    if(command && !strcmp(command,"AUTO\n")) return 3.5;
    return 0.8;
}
int bf_request(const char *path, const char *command, char *response, size_t capacity) {
    if(response && capacity) response[0]=0;
    if(!path || !command || !response || capacity<2) return -1;
    size_t length=strlen(command);
    if(!length || length>255 || command[length-1]!='\n' || memchr(command,'\n',length-1)) return -1;
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX;
    if(strlen(path)>=sizeof(address.sun_path)) return -1;
    strcpy(address.sun_path,path); address.sun_len=sizeof(address);
    int fd=socket(AF_UNIX,SOCK_STREAM,0); if(fd<0) return -1;
    int noSignal=1, result=-1;
    if(setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,sizeof(noSignal)) ||
       fcntl(fd,F_SETFD,FD_CLOEXEC)<0 || fcntl(fd,F_SETFL,O_NONBLOCK)<0) goto done;
    double deadline=monotime()+bf_request_timeout(command);
    if(connect(fd,(struct sockaddr*)&address,sizeof(address))) {
        if(errno!=EINPROGRESS || ready(fd,POLLOUT,deadline)) goto done;
        int error=0; socklen_t size=sizeof(error);
        if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&error,&size) || error) goto done;
    }
    uid_t uid; gid_t gid;
    if(getpeereid(fd,&uid,&gid) || uid!=0) goto done;
    size_t sent=0;
    while(sent<length) {
        if(ready(fd,POLLOUT,deadline)) goto done;
        ssize_t n=write(fd,command+sent,length-sent);
        if(n<0 && (errno==EINTR || errno==EAGAIN)) continue;
        if(n<=0) goto done; sent+=(size_t)n;
    }
    size_t used=0;
    while(used<capacity-1) {
        if(ready(fd,POLLIN,deadline)) goto done;
        ssize_t n=read(fd,response+used,capacity-1-used);
        if(n<0 && (errno==EINTR || errno==EAGAIN)) continue;
        if(n<=0) goto done;
        if(memchr(response+used,0,(size_t)n)) goto done;
        used+=(size_t)n; response[used]=0;
        char *newline=memchr(response,'\n',used);
        if(newline) { if(newline==response+used-1) result=0; goto done; }
    }
done:
    close(fd); if(result) response[0]=0; return result;
}
