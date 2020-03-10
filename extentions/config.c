#include <stdio.h>
#include <string.h>
#include <linux/limits.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdbool.h>
#include <time.h>
#include <syslog.h>

#include <syslog.h>

#include "postgres.h"
#include "audit.h"
#include "config.h"

#define DEBUG
#define ROLES_FILE "changetable.roles"

config_t *
config_init(void)
{
//    FILE *f = NULL;
//    char *l = NULL;
//    size_t n = 0, read;
//    privilege_t *priv, *last = NULL;

    config_t *config = malloc(sizeof(config_t));
    config->privs = NULL;

    // Read roles from config file
//    if ((f = fopen(ROLES_FILE, "r")) != NULL)
//    {
//        while ((read = getline(&l, &n, f)) != -1)
//        {
//            if (read > (NAMEDATALEN-1))
//                read =  NAMEDATALEN-1;

//            if (l[read-1] == '\n')
//                l[read-1] = 0x00;

//            if (strlen(l) == 0)
//                continue;

//#ifdef DEBUG
//            syslog(LOG_INFO, "config_init(): role '%s'", l);
//#endif

//            priv = malloc(sizeof(privilege_t));
//            memcpy(priv->role, l, read-1);
//            priv->next = NULL;

//            if (config->privs == NULL)
//                config->privs = priv;
//            else
//                last->next = priv;

//            last = priv;
//        }
//        if (l != NULL)
//            free(l);

//        fclose(f);
//    }
//    else
//    {
//        syslog(LOG_ERR, "Can't open config %s. No roles loaded!", ROLES_FILE);
//    }

    config->audit = audit_init();

//    syslog(LOG_INFO, "config_init(): ok");

    return config;
}


void
config_free(config_t *config)
{
    if (config->privs != NULL)
    {
        privilege_t *priv = config->privs;
        privilege_t *next = NULL;
        do {
            next = priv->next;
            free(priv);
            priv = next;
        } while (priv != NULL);
    }
    audit_free(config->audit);
    free(config);
}
