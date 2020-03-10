#ifndef AUDIT_H
#define AUDIT_H

typedef struct audit
{
    char root_path[PATH_MAX];
    char db_file[PATH_MAX];
} audit_t;

typedef struct audit_item
{
    int id;
    time_t time;
    char *query;
} audit_item_t;

audit_t *audit_init(void);
void audit_free(audit_t *a);
int audit_item_create(audit_t *a, const char *role, const char *sql);

audit_item_t *audit_item_init(void);
bool audit_item_read(audit_item_t *i, FILE *f);
void audit_item_print(audit_item_t *i);
void audit_item_free(audit_item_t *i);

#define audit_file_t void
audit_file_t *audit_open(audit_t *a);
void audit_close(audit_file_t *af);

bool audit_run_hook(audit_item_t *ai);

#endif
