#include "smc.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void) {
 char response[16]="stale";
 assert(bf_request(NULL,"PING\n",response,sizeof(response))==-1 && response[0]==0);
 assert(bf_request("/nonexistent",NULL,response,sizeof(response))==-1);
 assert(bf_request("/nonexistent","PING",response,sizeof(response))==-1);
 assert(bf_request("/nonexistent","PING\nAUTO\n",response,sizeof(response))==-1);
 assert(bf_request("/nonexistent","",response,sizeof(response))==-1);
 assert(bf_request("/nonexistent","PING\n",response,1)==-1);
 assert(bf_key_at(0,NULL)==-1);
 assert(bf_fan_bounds(0,NULL,NULL)==-1);
 assert(bf_fan_bounds(-1,NULL,NULL)==-1);
 puts("Transport: malformed frames, null arguments and response initialization passed.");
}
