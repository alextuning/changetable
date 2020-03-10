#ifndef CONFIG_H
#define CONFIG_H

#include "audit.h"

typedef enum operation
{
    INSERT,
    UPDATE,
    DELETE
} operation_t;

typedef struct privilege
{
    char role[NAMEDATALEN];
//    char *role;
    struct privilege *next;
} privilege_t;

typedef struct config
{
    char *roles;
    privilege_t *privs;
    unsigned int privs_size;
    audit_t *audit;
} config_t;

config_t *config_init(void);
void config_free(config_t *config);

#endif
