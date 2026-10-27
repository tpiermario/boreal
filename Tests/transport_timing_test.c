// Peer authentication is mocked only in this test translation unit.
// Production smc.c still calls the system getpeereid and requires UID 0.
#define getpeereid test_getpeereid
#include "../Sources/CSMC/smc.c"
#undef getpeereid
#include <assert.h>
#include <pthread.h>
int test_getpeereid(int fd, uid_t *uid, gid_t *gid) { (void)fd; *uid=0; *gid=0; return 0; }
struct fixture { int server; useconds_t delay; const char *reply; };
static void *serve(void *context) {
    struct fixture *f=context;
    int client=accept(f->server,NULL,NULL); assert(client>=0);
    int one=1; setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&one,sizeof(one));
    char c; while(read(client,&c,1)==1 && c!='\n') {}
    usleep(f->delay);
    (void)write(client,f->reply,strlen(f->reply)); close(client); return NULL;
}
static void request_case(const char *command, useconds_t delay, int expected, const char *reply) {
    char directory[]="/tmp/boreal-transport.XXXXXX"; assert(mkdtemp(directory));
    struct sockaddr_un address={0}; address.sun_family=AF_UNIX; address.sun_len=sizeof(address);
    snprintf(address.sun_path,sizeof(address.sun_path),"%s/socket",directory);
    int fd=socket(AF_UNIX,SOCK_STREAM,0); assert(fd>=0);
    assert(!bind(fd,(struct sockaddr*)&address,sizeof(address))); assert(!listen(fd,1));
    struct fixture f={fd,delay,reply}; pthread_t thread; assert(!pthread_create(&thread,NULL,serve,&f));
    char response[64]="old"; double start=monotime();
    assert(bf_request(address.sun_path,command,response,sizeof(response))==expected);
    double elapsed=monotime()-start;
    if(expected==0) assert(!strcmp(response,reply)); else assert(response[0]==0);
    assert(elapsed < bf_request_timeout(command)+0.6);
    assert(!pthread_join(thread,NULL)); close(fd); unlink(address.sun_path); rmdir(directory);
}
int main(void) {
    assert(bf_request_timeout("PING\n")==0.8);
    assert(bf_request_timeout("AUTO\n")==3.5);
    assert(bf_request_timeout("APPLY 2000\n")==5.5);
    request_case("APPLY 2000\n",2200000,0,"OK\n");
    request_case("APPLY 2000\n",4200000,0,"ERR SMC-stage -14\n");
    request_case("AUTO\n",1200000,0,"OK\n");
    request_case("PING\n",1200000,-1,"OK 1\n");
    request_case("APPLY 2000\n",5800000,-1,"OK\n");
    puts("Transport timing: delayed apply, rollback, auto, bounded timeout and fast ping passed.");
}
