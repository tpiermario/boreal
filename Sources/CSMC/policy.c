#include "smc.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int bf_valid_target(double rpm, double minimum, double maximum) {
    return isfinite(rpm) && isfinite(minimum) && isfinite(maximum)
        && minimum >= 0 && maximum > minimum && maximum <= 20000
        && rpm >= minimum && rpm <= maximum;
}
double bf_curve(double t, double start, double full, double lo, double hi) {
    if (!isfinite(t) || !isfinite(start) || !isfinite(full) || !isfinite(lo)
        || !isfinite(hi) || full <= start || lo < 0 || hi <= lo || hi > 20000) return NAN;
    double progress = fmax(0, fmin(1, (t - start) / (full - start)));
    return lo + progress * (hi - lo);
}
int bf_parse_targets(const char *command, int count, double targets[10]) {
    if(!command || !targets || count<1 || count>10 || strncmp(command,"APPLY ",6)) return -1;
    const char *p=command+6;
    for(int i=0;i<count;i++) {
        if (!((*p>='0' && *p<='9') || *p=='-')) return -1;
        const char *token=p;
        if(*token=='-') token++;
        if(*token<'0' || *token>'9') return -1;
        while(*token>='0' && *token<='9') token++;
        if(*token=='.') {
            token++;
            if(*token<'0' || *token>'9') return -1;
            while(*token>='0' && *token<='9') token++;
        }
        if(*token && *token!=' ') return -1;
        char *end; errno=0; targets[i]=strtod(p,&end);
        if(p==end || errno || !isfinite(targets[i]) || targets[i]>20000 || (targets[i]<0 && targets[i]!=-1)) return -1;
        p=end;
        if(i<count-1) { if(*p!=' ') return -1; p++; if(!*p || *p==' ') return -1; }
    }
    return *p ? -1 : 0;
}

uint16_t bf_mode_bits(uint16_t bits, int fan, int manual) {
    if(fan<0 || fan>=10) return bits;
    uint16_t mask=(uint16_t)(1u<<fan);
    return manual ? (uint16_t)(bits|mask) : (uint16_t)(bits&~mask);
}
