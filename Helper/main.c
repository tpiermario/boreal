#include "smc.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <fcntl.h>
#include <sys/file.h>
#include <mach/mach_time.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>

static volatile sig_atomic_t running=1;
static int leased=0;
static io_connect_t powerPort=0;
static void stop(int sig) { (void)sig; running=0; }
static double now(void) {
    mach_timebase_info_data_t scale; mach_timebase_info(&scale);
    return (double)mach_continuous_time() * scale.numer / scale.denom / 1e9;
}
static void power_event(void *context,io_service_t service,natural_t message,void *argument) {
    (void)context; (void)service;
    if(message==kIOMessageSystemWillSleep) {
        leased=bf_restore_all()!=0; IOAllowPowerChange(powerPort,(long)argument);
    } else if(message==kIOMessageCanSystemSleep) IOAllowPowerChange(powerPort,(long)argument);
}
static int lease_expired(double last, double current) { return current-last>4; }
static int temperatures_safe(void) {
    const char *keys[]={"TC0P","TC0D","TC0E","TC0F","TC0H","TCXC","TCGC","TG0P","TG0D"};
    int foundCPU=0;
    for(size_t i=0;i<sizeof(keys)/sizeof(keys[0]);i++) {
        double t; if(bf_number(keys[i],&t)) continue;
        if(!isfinite(t) || t<=0 || t>125) return 0;
        if(i<7) foundCPU=1;
        if(t>=95) return 0;
    }
    return foundCPU;
}
static int apply(char *line, int count) {
    if(!strcmp(line,"AUTO")) return bf_restore_all();
    double targets[10];
    if(bf_parse_targets(line,count,targets)) return -1;
    int manual=0; for(int i=0;i<count;i++) if(targets[i]!=-1) manual=1;
    if(!manual) return bf_restore_all();
    if(!temperatures_safe()) { bf_restore_all(); return -2; }
    for(int i=0;i<count;i++) {
        if(targets[i]!=-1) {
            double lo,hi; if(!bf_can_control(i) || bf_fan_bounds(i,&lo,&hi)
                || !bf_valid_target(targets[i],lo,hi)) return -1;
        }
    }
    for(int i=0;i<count;i++) {
        int rc=targets[i]==-1?bf_fan_auto(i):bf_fan_set(i,targets[i]);
        if(rc) { bf_restore_all(); return rc; }
    }
    return 0;
}
int main(int argc,char **argv) {
    if(geteuid()!=0 || argc!=2 || !bf_intel_hardware()) { fprintf(stderr,"Run installed helper on Intel as root with an authorized UID.\n"); return 1; }
    char *end; errno=0; unsigned long user=strtoul(argv[1],&end,10);
    if(errno || end==argv[1] || *end || user<501 || user>UINT32_MAX) return 1;
    int lock=open("/var/run/it.boreal.fans.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600);
    struct stat lockstat;
    if(lock<0 || fstat(lock,&lockstat) || !S_ISREG(lockstat.st_mode) || lockstat.st_uid!=0 || flock(lock,LOCK_EX|LOCK_NB)) return 3;
    if(bf_open()) { fprintf(stderr,"AppleSMC unavailable\n"); return 2; }
    int count=bf_fan_count(); if(count<1 || count>10) return 2;
    if(bf_restore_all()) { fprintf(stderr,"Unable to establish automatic mode\n"); return 2; }
    char path[100]; snprintf(path,sizeof(path),"/var/run/it.boreal.fans.%lu.sock",user);
    struct stat st; if(!lstat(path,&st)) {
        if(!S_ISSOCK(st.st_mode) || (st.st_uid!=0 && st.st_uid!=(uid_t)user)) return 3;
        if(unlink(path)) return 3;
    }
    int server=socket(AF_UNIX,SOCK_STREAM,0); if(server<0) return 3;
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX; address.sun_len=sizeof(address); strcpy(address.sun_path,path);
    umask(0077);
    if(bind(server,(struct sockaddr*)&address,sizeof(address)) || chown(path,(uid_t)user,0)
       || chmod(path,0600) || listen(server,8)) { close(server); unlink(path); return 3; }
    signal(SIGTERM,stop); signal(SIGINT,stop); signal(SIGPIPE,SIG_IGN);
    IONotificationPortRef notificationPort=NULL; io_object_t notifier=0;
    powerPort=IORegisterForSystemPower(NULL,&notificationPort,power_event,&notifier);
    if(!powerPort || !notificationPort) { fprintf(stderr,"Power notifications unavailable\n"); close(server); unlink(path); bf_close(); return 5; }
    if(powerPort && notificationPort)
        CFRunLoopAddSource(CFRunLoopGetCurrent(),IONotificationPortGetRunLoopSource(notificationPort),kCFRunLoopDefaultMode);
    double last=now();
    while(running) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,0,true);
        /* Expiry, wake and thermal checks run independently of the app. */
        if(leased && (lease_expired(last,now()) || !temperatures_safe())) { leased=bf_restore_all()!=0; }
        struct pollfd poller={.fd=server,.events=POLLIN};
        int ready=poll(&poller,1,100);
        if(ready<0 && errno!=EINTR) break;
        if(ready<=0 || !(poller.revents&POLLIN)) continue;
        int client=accept(server,NULL,NULL); if(client<0) continue;
        uid_t uid; gid_t gid;
        if(getpeereid(client,&uid,&gid) || uid!=(uid_t)user) { close(client); continue; }
        struct timeval timeout={.tv_sec=0,.tv_usec=200000};
        setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
        char line[256]={0}; size_t used=0; int complete=0; double receiveStart=now();
        while(used<sizeof(line)-1) {
            char ch; if(read(client,&ch,1)!=1) break;
            if(ch=='\n') {complete=1;break;} if(ch==0) break; line[used++]=ch;
            /* Slow byte streams cannot extend the watchdog window. */
            if(lease_expired(last,now()) && leased) {leased=bf_restore_all()!=0;break;}
            if(now()-receiveStart>0.5) break;
        }
        int ping=complete && !strcmp(line,"PING");
        int rc=ping?0:complete && running?apply(line,count):-1;
        char diagnostic[80]; snprintf(diagnostic,sizeof(diagnostic),"ERR SMC-stage %d\n",rc);
        const char *reply=rc<=-10?diagnostic:ping?"OK 1\n":rc==0?"OK\n":rc==-2?"ERR thermal-or-sensor\n":"ERR rejected-or-SMC\n";
        if(ping) { /* Health check never changes the lease or SMC state. */ }
        else if(!rc) { last=now(); leased=strncmp(line,"APPLY ",6)==0; }
        else { leased=bf_restore_all()!=0; }
        (void)write(client,reply,strlen(reply)); close(client);
    }
    int result=bf_restore_all(); close(server); unlink(path);
    if(powerPort) { IODeregisterForSystemPower(&notifier); IOServiceClose(powerPort); }
    if(notificationPort) IONotificationPortDestroy(notificationPort);
    close(lock); bf_close(); return result?4:0;
}
