#include "smc.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

int main(int argc,char **argv) {
    if(argc!=2 || (strcmp(argv[1],"--status") && strcmp(argv[1],"--auto") && strcmp(argv[1],"--max") && strcmp(argv[1],"--ping"))) {
        fprintf(stderr,"Uso: borealctl --status | --auto | --max | --ping\n"); return 1;
    }
    char command[256]="AUTO\n";
    if(!strcmp(argv[1],"--ping")) strcpy(command,"PING\n");
    else if(strcmp(argv[1],"--auto")) {
        if(bf_open()) { fprintf(stderr,"AppleSMC non accessibile\n"); return 2; }
        int n=bf_fan_count(); if(n<1 || n>10) { fprintf(stderr,"Nessuna ventola riconosciuta\n"); return 2; }
        if(!strcmp(argv[1],"--status")) {
            for(int i=0;i<n;i++) {
                char key[5]; double rpm,lo,hi; snprintf(key,5,"F%dAc",i);
                if(bf_number(key,&rpm) || bf_fan_bounds(i,&lo,&hi)) { fprintf(stderr,"Lettura non riuscita\n"); return 2; }
                printf("fan%d current=%.0f min=%.0f max=%.0f controllable=%d mode=%d\n",i,rpm,lo,hi,bf_can_control(i),bf_fan_mode(i));
            }
            bf_close(); return 0;
        }
        strcpy(command,"APPLY ");
        for(int i=0;i<n;i++) {
            double lo,hi; if(bf_fan_bounds(i,&lo,&hi)) return 2;
            size_t used=strlen(command);
            snprintf(command+used,sizeof(command)-used,"%.2f%s",hi,i==n-1?"\n":" ");
        }
        bf_close();
    }
    char path[100],response[256]; snprintf(path,sizeof(path),"/var/run/it.boreal.fans.%u.sock",getuid());
    if(bf_request(path,command,response,sizeof(response))) { fprintf(stderr,"Servizio non raggiungibile\n"); return 3; }
    fputs(response,stdout);
    if(!strcmp(argv[1],"--max")) puts("Richiesta singola: senza heartbeat il controllo torna ad Auto dopo 4 secondi.");
    return strcmp(response,!strcmp(argv[1],"--ping")?"OK 1\n":"OK\n")?4:0;
}
