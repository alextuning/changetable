#include <stdio.h>
#include <string.h>
#include <linux/limits.h>
//#include <openssl/md5.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>
#include <syslog.h>

#include "postgres.h"

#include "misc.h"
#include "audit.h"


#define AUDIT_ROOT_PATH "audit"
#define AUDIT_LOG_FILE_NAME "audit.log"
#define ITEM_ID_SIZE 32

void audit_list_items(audit_t *a);
int audit_item_add(audit_t *a,
               char *sqltext, int sqltext_size,
               char *comment, int comment_size);
//void md5(const char *str, char *out);



audit_t*
audit_init(void)
{
    audit_t *obj = (audit_t*) malloc(sizeof(audit_t));
    struct stat s = {0};

    snprintf(obj->root_path, PATH_MAX, "./%s", AUDIT_ROOT_PATH);
    if (stat(obj->root_path, &s) == -1)
        mkdir(obj->root_path, 0755);

    snprintf(obj->db_file, PATH_MAX, "./%s", AUDIT_LOG_FILE_NAME);
    if (stat(obj->db_file, &s) == -1)
    {
        FILE *f = fopen(obj->db_file, "w");
        fclose(f);
    }

    return obj;
}

void
audit_free(audit_t *obj)
{
    free(obj);
}

//void
//md5(const char *str, char *out)
//{
//    unsigned char digest[16];
//    int i;
//    MD5_CTX context;

//    MD5_Init(&context);
//    MD5_Update(&context, str, strlen(str));
//    MD5_Final(digest, &context);

//    for(i = 0; i < MD5_DIGEST_LENGTH; i++)
//        sprintf(&out[i*2],"%02x", digest[i]);
//}


audit_item_t *audit_item_init(void)
{
    audit_item_t *i = malloc(sizeof(audit_item_t));
    i->id = 0;
    i->time = 0;
    i->query = NULL;
    return i;
}

void
audit_item_free(audit_item_t *i)
{
    if (i->query != NULL)
        free(i->query);
    free(i);
}

int
audit_item_add(audit_t *a,
               char *sqltext, int sqltext_size,
               char *comment, int comment_size)
{
    FILE *f;
    int last_id = 0;
    struct stat s = {0};
    time_t rawtime = time(NULL);


    if (rawtime == -1)
    {
        fputs("audit_item_add(): The time() function failed", stderr);
        return 1;
    }

    stat(a->db_file, &s);

    f = fopen(a->db_file, "ab+");
    if (f == NULL)
    {
        fputs("audit_item_add(): File open error", stderr);
        return 2;
    }

    /*
     * Read last audit_item id
    */
    if (s.st_size > 0)
    {
        fseek(f, s.st_size-sizeof(int), SEEK_SET);
        if (fread(&last_id, 1, sizeof(int), f) < 1)
        {
            fputs("audit_item_add(): Can't read previous id", stderr);
            return 3;
        }
        last_id++;
    }

    fwrite(&rawtime, 1, sizeof(time_t), f);
    fwrite(&sqltext_size, 1, sizeof(int), f);
    fwrite(sqltext, 1, sqltext_size, f);
    fwrite(&comment_size, 1, sizeof(int), f);
    fwrite(comment, 1, comment_size, f);
    fwrite(&last_id, 1, sizeof(int), f);

    fclose(f);
    return 0;
}

bool
audit_item_read(audit_item_t *i, FILE *f)
{
//    size_t s = 0;
//    char buf[2];

//    s = fread(&i->time, 1, sizeof(time_t), f);
//    s = fread(&buf, 1, 1, f);
//    if (s < 1)
//        return false;
//    // sql size
//    s = fread(&i->sqltext_size, 1, sizeof(int), f);
//    // sql text
//    i->sqltext = calloc(i->sqltext_size + 1, 1);
//    s = fread(i->sqltext, 1, i->sqltext_size, f);
//    // comment size
//    s = fread(&i->comment_size, 1, sizeof(int), f);
//    // comment text
//    i->comment = calloc(i->comment_size + 1, 1);
//    s = fread(i->comment, i->comment_size, 1, f);
//    // read id
//    s = fread(&i->id, 1, sizeof(int), f);

    return true;
}

int
audit_item_create(audit_t *a, const char *role, const char *query)
{
//    char *comment_s = NULL;
//    char *comment_e = NULL;
    audit_item_t *ai;
    int qlen = strlen(query);

    ai = audit_item_init();
    ai->time = time(NULL);
    ai->query = malloc(qlen + 1);
    memset(ai->query, 0, qlen + 1);
    memcpy(ai->query, query, qlen);

    if (audit_run_hook(ai) == false)
    {
        syslog(LOG_INFO, "audit_item_create(): rejected by hook");
        return 1;
    }

//    comment_s = strstr(query, "/*");
//    comment_e = strstr(query, "*/");

//    if (comment_s == NULL || comment_e == NULL)
//    {
//        syslog(LOG_INFO, "audit_item_create(): no comment found");
//        return 2;
//    }
//    if (comment_s >= comment_e)
//    {
//        syslog(LOG_INFO, "audit_item_create(): comment end before begin");
//        return 3;
//    }

    audit_item_free(ai);
    return 0;
}

void
audit_item_print(audit_item_t *i)
{
    char time_str_buf[20];
    time_to_str(i->time, time_str_buf, 20);
    printf("%d %s %s\n", i->id, time_str_buf, i->query);
}

audit_file_t*
audit_open(audit_t *a)
{
    FILE *f = fopen(a->db_file, "rb");
    if (f == NULL)
    {
        fputs("File open error", stderr);
        return NULL;
    }
    return (audit_file_t*)f;
}

void audit_close(audit_file_t *af)
{
    fclose((FILE*)af);
}

void
audit_list_items(audit_t *a)
{
    audit_file_t *f;
    audit_item_t *i;

    f = audit_open(a);
    if (f == NULL)
        return;

    while (true)
    {
        i = audit_item_init();
        if (audit_item_read(i, f) == false)
            break;

        audit_item_print(i);
        audit_item_free(i);
    }
    audit_close(f);
}

bool
audit_run_hook(audit_item_t *ai)
{
    int ret = 0;

    FILE* f = popen("changetable-hook", "w");
    if (f == NULL)
    {
        syslog(LOG_WARNING, "audit_run_hook(): unable to create hook process: %s", strerror(errno));
        return false;
    }

    fprintf(f, "%s\n", ai->query);

    ret = pclose(f);
    if (ret > 0)
    {
        syslog(LOG_INFO, "audit_run_hook(): hook return code %d", ret);
        return false;
    }
    if (ret < 0)
    {
        syslog(LOG_ERR, "audit_run_hook(): hook error: %s", strerror(errno));
        return false;
    }

    return true;
}
