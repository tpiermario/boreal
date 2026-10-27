#define main boreal_helper_main
#include "../Helper/main.c"
#undef main
#include <assert.h>
static double temperature=60;
static int restored=0, writes=0, failure=0;
int bf_intel_hardware(void){return 1;}
int bf_open(void){return 0;}
void bf_close(void){}
int bf_fan_count(void){return 2;}
int bf_number(const char *k,double *v){(void)k; *v=temperature;return 0;}
int bf_restore_all(void){restored++;return 0;}
int bf_can_control(int fan){return fan>=0 && fan<2;}
int bf_fan_bounds(int fan,double *lo,double *hi){(void)fan;*lo=1000;*hi=5000;return 0;}
int bf_fan_auto(int fan){(void)fan;return 0;}
int bf_fan_set(int fan,double rpm){(void)fan;(void)rpm;writes++;return failure;}
int main(void){
    assert(!lease_expired(10,14));
    assert(lease_expired(10,14.001));
    assert(lease_expired(10,100));
    assert(apply("AUTO",2)==0 && restored==1);
    assert(apply("APPLY 2000 3000",2)==0 && writes==2);
    assert(apply("APPLY 999 3000",2)!=0 && writes==2);
    assert(apply("APPLY 2000 5001",2)!=0 && writes==2);
    temperature=0; assert(!temperatures_safe());
    assert(apply("APPLY 2000 3000",2)==-2 && writes==2);
    assert(apply("APPLY -1 -1",2)==0);
    temperature=NAN; assert(!temperatures_safe());
    temperature=95; assert(!temperatures_safe());
    temperature=94.9; assert(temperatures_safe());
    failure=1; int before=restored; assert(apply("APPLY 2000 3000",2)!=0 && restored>before);
    double targets[10];
    const char *bad[]={"APPLY  2000 3000","APPLY \t2000 3000","APPLY +2000 3000","APPLY 20001 3000","APPLY 2000","APPLY 2000 3000 extra","APPLY nan 3000","APPLY 0x800 3000","APPLY 2e3 3000","APPLY 2000. 3000","APPLY - 3000"};
    for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++) assert(bf_parse_targets(bad[i],2,targets)!=0);
    assert(isnan(bf_curve(50,30,80,1000,30000)));
    puts("Helper regression: thermal protection, preflight, auto, rollback and malformed commands passed.");
    return 0;
}
