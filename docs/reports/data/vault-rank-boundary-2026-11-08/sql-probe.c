#include <sqlite3.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static double deadline;
static int cancelled(void *unused) { return now()>deadline; }
static uint64_t hash(uint64_t value,const unsigned char *bytes,size_t count) {
    for(size_t i=0;i<count;i++) value=(value^bytes[i])*1099511628211ULL;
    return value;
}
int main(int argc,char **argv) {
    if(argc!=4)return 2;
    FILE *file=fopen(argv[2],"rb");if(!file)return 3;
    char sql[16384];size_t bytes=fread(sql,1,sizeof(sql)-1,file);fclose(file);sql[bytes]=0;
    sqlite3 *db=NULL;
    if(sqlite3_open_v2(argv[1],&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX,NULL)!=SQLITE_OK)return 4;
    sqlite3_stmt *statement=NULL;deadline=now()+45;
    sqlite3_progress_handler(db,10000,cancelled,NULL);
    double start=now();int result=sqlite3_prepare_v2(db,sql,-1,&statement,NULL);
    if(result!=SQLITE_OK) {fprintf(stderr,"%s\n",sqlite3_errmsg(db));return 5;}
    sqlite3_bind_text(statement,1,"\"meeting\"*",-1,SQLITE_STATIC);
    int count=0;uint64_t fingerprint=14695981039346656037ULL;
    while((result=sqlite3_step(statement))==SQLITE_ROW) {
        const unsigned char *id=sqlite3_column_text(statement,0);
        fingerprint=hash(fingerprint,id,sqlite3_column_bytes(statement,0));
        double score=sqlite3_column_double(statement,1);
        fingerprint=hash(fingerprint,(const unsigned char*)&score,sizeof(score));count++;
    }
    printf("{\"variant\":\"%s\",\"seconds\":%.6f,\"rows\":%d,\"fingerprint\":\"%016llx\",\"sqliteResult\":%d,\"sqliteVersion\":\"%s\"}\n",argv[3],now()-start,count,(unsigned long long)fingerprint,result,sqlite3_libversion());
    if(result!=SQLITE_DONE)fprintf(stderr,"%s\n",sqlite3_errmsg(db));
    sqlite3_finalize(statement);sqlite3_close(db);return result==SQLITE_DONE?0:6;
}
