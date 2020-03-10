#include <syslog.h>

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "tcop/utility.h"
#include "funcapi.h"
#include "utils/acl.h"

#include "audit.h"
#include "config.h"
#include "misc.h"

#define MODULE_VERSION "0.1.14"
//#define DEBUG

PG_MODULE_MAGIC;

void _PG_init(void);
void _PG_fini(void);

/* Saved hook values in case of unload */
static ExecutorRun_hook_type original_executor_run_hook = NULL;

#ifdef BUILD_PG_VER_10
static void executor_run_hook(QueryDesc *queryDesc, ScanDirection direction, long count, bool execute_once);
#else
static void executor_run_hook(QueryDesc *queryDesc, ScanDirection direction, long count);
#endif

#ifdef DEVHOOK
static ExecutorStart_hook_type original_executor_start_hook = NULL;
static ProcessUtility_hook_type original_utility_hook = NULL;
static ExecutorCheckPerms_hook_type original_executor_check_perms_hook = NULL;

static void process_utility_hook(Node *parsetree, const char *queryString,
                                ParamListInfo params, bool isTopLevel,
                                DestReceiver *dest, char *completionTag);
static void executor_start_hook(QueryDesc *queryDesc, int eflags);
static bool executor_check_perms_hook(List *rangeTabls, bool abort);
#endif

bool is_role_in_config(char *role);
char *escape_single_quote(const char *query);
bool validate_procedure(CmdType operation, const char *query);
bool handle_query(const char *role, CmdType operation, const char *query);

#ifdef DEBUG
Datum spiexec(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(spiexec);
#endif

const char * CMD_TYPE_STR[] =
{
    "UNKNOWN",
    "SELECT",                 /* select stmt */
    "UPDATE",                 /* update stmt */
    "INSERT",                 /* insert stmt */
    "DELETE",
    "UTILITY",                /* cmds like create, destroy, copy, vacuum, etc. */
    "NOTHING"                 /* dummy command for instead nothing rules with qual */
};

config_t *config = NULL;

void
_PG_init(void)
{
    openlog("changetable", 0, LOG_USER);

    original_executor_run_hook = ExecutorRun_hook;
    ExecutorRun_hook = executor_run_hook;

#ifdef DEVHOOK
    original_utility_hook = ProcessUtility_hook;
    ProcessUtility_hook = process_utility_hook;
    
    original_executor_start_hook = ExecutorStart_hook;
    ExecutorStart_hook = executor_start_hook;
    
    original_executor_check_perms_hook = ExecutorCheckPerms_hook;
    ExecutorCheckPerms_hook = executor_check_perms_hook;
#endif
    
    config = config_init();
    elog(INFO, "changetable ver %s loaded", MODULE_VERSION);
}

void
_PG_fini(void)
{
    syslog(LOG_INFO, "pg_fini()");
    ExecutorRun_hook = original_executor_run_hook;

#ifdef DEVHOOK
    ProcessUtility_hook = original_utility_hook;
    ExecutorStart_hook = original_executor_start_hook;
    ExecutorCheckPerms_hook = original_executor_check_perms_hook;
#endif
    
    config_free(config);
    closelog();
}

bool
is_role_in_config(char *role)
{
    privilege_t *priv = config->privs;
    while (priv != NULL)
    {
        if (strcmp(priv->role, role) == 0)
        {
#ifdef DEBUG
            elog (INFO, "is_role_in_config(): %s TRUE", priv->role);
#endif
            return true;
        }
        priv = priv->next;
    }
#ifdef DEBUG
    elog (INFO, "is_role_in_config(): %s FALSE", role);
#endif
    return false;
}

char *
escape_single_quote(const char *query)
{
    char *buffer = NULL;
    char *chr = NULL;
    char *ptr = NULL;
    char *end = NULL;
    char *search_ptr = NULL;
    int index = 0;
    int len = strlen(query);
    int buffer_size = len + 10;

    buffer = malloc(buffer_size);
    memcpy(buffer, query, len + 1);
    search_ptr = buffer;

    while (true)
    {
        chr = strchr(search_ptr, 0x27); // single quote
        if (!chr)
            break;

        index = chr - buffer;

        if (len + 1 > buffer_size - 1)
        {
            buffer_size += 10;
            buffer = realloc(buffer, buffer_size);
            if (buffer == NULL)
            {
                printf("escape_single_quote(): realloc failed");
                return NULL;
            }
        }

        len++;
        chr = &buffer[index];
        end = &buffer[len + 1];

        ptr = end;
        while (ptr != chr)
        {
            *ptr = *(ptr-1);
            ptr--;
        }
        *chr = '\\';    // escape character
        *end = 0x00;

        search_ptr = chr + 2;

        if (search_ptr >= end)
            break;
    }

    return buffer;
}

bool
validate_procedure(CmdType operation, const char *query)
{
    int ret;
    bool is_valid = true;

    char *escaped_query_string = NULL;
    int escaped_query_string_s = 0;

    char *query_template = "SELECT ss_util.validate('%s', E'%s');";
    int query_template_s = strlen(query_template);

    char *buffer = NULL;
    int buffer_s = 0;

    escaped_query_string = escape_single_quote(query);
    escaped_query_string_s = strlen(escaped_query_string);

    buffer_s = query_template_s + strlen(CMD_TYPE_STR[operation]) + escaped_query_string_s + 1;
    buffer = malloc(buffer_s);
    if (buffer == NULL)
    {
        syslog(LOG_ERR, "validate_procedure(): malloc failed");
        return false;
    }

    snprintf(buffer, buffer_s, query_template,
             CMD_TYPE_STR[operation], escaped_query_string);

    SPI_connect();
    ret = SPI_exec(buffer, 1);
    if (ret == SPI_OK_SELECT && SPI_processed > 0)
    {
        TupleDesc tupdesc = SPI_tuptable->tupdesc;
        SPITupleTable *tuptable = SPI_tuptable;
        HeapTuple tuple = tuptable->vals[0];

        if (strncmp(SPI_getvalue(tuple, tupdesc, 1), "t", 1) != 0)
            is_valid = false;
    }
    else
    {
        elog(ERROR, "validate_procedure(): spi_exec failed, something wrong");
        is_valid = false;
    }

    SPI_finish();
    free(escaped_query_string);
    free(buffer);
    return is_valid;
}

// TODO:
//void
//ct_list(void)
//{
//    audit_file_t *f;
//    audit_item_t *i;
//    char time_str_buf[20];
//    elog(INFO, "=== LIST ===");
//    f = audit_open(config->audit);
//    if (f == NULL)
//    {
//        elog(ERROR, "Can't open file %s", config->audit->db_file);
//        return;
//    }
//    while (true)
//    {
//        i = audit_item_init();
//        // i is NULL ??
//        if (audit_item_read(i, f) == false)
//            break;
//        time_to_str(i->time, time_str_buf, 20);
//        elog(INFO, "%d %s %s %s", i->id, time_str_buf, i->sqltext, i->comment);
//        audit_item_free(i);
//    }
//    audit_close(f);
//    return;
//}


#ifdef BUILD_PG_VER_10
static
void executor_run_hook(QueryDesc *queryDesc, ScanDirection direction, long count, bool execute_once)
{
    char *role = GetUserNameFromId(GetUserId(), false);

    if (!handle_query(role, queryDesc->operation, queryDesc->sourceText))
        return;

    if (original_executor_run_hook)
        (*original_executor_run_hook)(queryDesc, direction, count, execute_once);
    else
        standard_ExecutorRun(queryDesc, direction, count, execute_once);
}
#else
static
void executor_run_hook(QueryDesc *queryDesc, ScanDirection direction, long count)
{
#ifdef BUILD_PG_VER_92
    char *role = GetUserNameFromId(GetUserId());
#else
    char *role = GetUserNameFromId(GetUserId(), false);
#endif

#ifdef DEBUG
    elog(INFO, "executor_run_hook(): role=%s", role);
#endif

    if (!handle_query(role, queryDesc->operation, queryDesc->sourceText))
        return;

    if (original_executor_run_hook)
        (*original_executor_run_hook)(queryDesc, direction, count);
    else
        standard_ExecutorRun(queryDesc, direction, count);
}
#endif

bool
handle_query(const char *role, CmdType operation, const char *query)
{
    switch(operation)
    {
    case CMD_INSERT:
        if (strstr(query, "ss_util.all_tables_log"))
            break;
    case CMD_UPDATE:
    case CMD_DELETE:
        if (validate_procedure(operation, query) == false)
        {
            syslog(LOG_ALERT, "%s: validation failed (%s)", role, query);
            elog(ERROR, "Query validation failed");
            return false;
        }
        if (audit_item_create(config->audit, role, query) != 0)
        {
            syslog(LOG_ALERT, "%s: audit failed (%s)", role, query);
            elog(ERROR, "Audit failed");
            return false;
        }
        syslog(LOG_INFO, "%s: %s", role, query);
        break;
    default:
        break;
    }

    return true;
}

#ifdef DEVHOOK
static
void executor_run_hook_global(QueryDesc *queryDesc, ScanDirection direction, long count)
{
#ifdef BUILD_PG_VER_92
    char *role = GetUserNameFromId(GetUserId());
#endif

#ifdef BUILD_PG_VER_95
    char *role = GetUserNameFromId(GetUserId(), false);
#endif

#ifdef DEBUG
    elog(INFO, "executor_run_hook(): role=%s", role);
#endif

    if (is_role_in_config(role))
    {
        switch(queryDesc->operation)
        {
        case CMD_INSERT:
        case CMD_UPDATE:
        case CMD_DELETE:
            if (validate_procedure(queryDesc->operation, queryDesc->sourceText) == false)
            {
                syslog(LOG_ALERT, "%s: validation failed (%s)", role, queryDesc->sourceText);
                elog(ERROR, "Query validation failed");
                return;
            }
            if (audit_item_create(config->audit, role, queryDesc->sourceText) != 0)
            {
                syslog(LOG_ALERT, "%s: audit failed (%s)", role, queryDesc->sourceText);
                elog(ERROR, "executor_run_hook(): audit failed");
                return;
            }
            syslog(LOG_INFO, "%s: %s", role, queryDesc->sourceText);
            break;
        default:
            break;
        }
    }

    if (original_executor_run_hook)
        (*original_executor_run_hook)(queryDesc, direction, count);
    else
        standard_ExecutorRun(queryDesc, direction, count);
}

static
void process_utility_hook(Node *parsetree,
                          const char *queryString,
                          ParamListInfo params, bool isTopLevel,
                          DestReceiver *dest, char *completionTag)
{
//    elog(INFO, "process_utility_hook(): user=%s", GetUserNameFromId(GetUserId()));
    
//    if (is_role_in_config(GetUserNameFromId(GetUserId())))
//    {
//        /* Do our custom process on drop database */
//        switch (nodeTag(parsetree))
//        {
//            case T_SelectStmt: { elog(NOTICE, "process_utility_hook: SELECT statement"); break; }
//            case T_UpdateStmt: { elog(NOTICE, "process_utility_hook: UPDATE statement"); break; }
//            case T_InsertStmt: { elog(NOTICE, "process_utility_hook: INSERT statement"); break; }
//            case T_DeleteStmt: { elog(NOTICE, "process_utility_hook: DELETE statement"); break; }
//        default: break;
//        }
//    }

    /*
     * Fallback to normal process, be it the previous hook loaded
     * or the in-core code path if the previous hook does not exist.
     */
    if (original_utility_hook)
        (*original_utility_hook)(parsetree, queryString,
            params, isTopLevel, dest, completionTag);
    else
        standard_ProcessUtility(parsetree, queryString,
            params, isTopLevel, dest, completionTag);
}

static
void executor_start_hook(QueryDesc *queryDesc, int eflags)
{
//   elog(INFO, "executor_start_hook(): user=%s", GetUserNameFromId(GetUserId()));

//   if (is_role_in_config(GetUserNameFromId(GetUserId())))
//   {
//       switch(queryDesc->operation)
//       {
//        case CMD_INSERT: elog(INFO, "CMD_INSERT"); audit_create_item(config->audit, queryDesc->sourceText); break;
//        case CMD_UPDATE: elog(INFO, "CMD_UPDATE"); audit_create_item(config->audit, queryDesc->sourceText); break;
//        case CMD_DELETE: elog(INFO, "CMD_DELETE"); audit_create_item(config->audit, queryDesc->sourceText); break;
//       default:
//           break;
//       }
//   }
  
  if (original_executor_start_hook)
        original_executor_start_hook(queryDesc, eflags);
    else
        standard_ExecutorStart(queryDesc, eflags);
}

static
bool executor_check_perms_hook(List *rangeTable, bool abort)
{
//    elog(INFO, "executor_check_perms_hook(), abort=%s, user=%s",
//         abort?"true":"false", GetUserNameFromId(GetUserId()));
    return true;
}
#endif

#ifdef DEBUG
Datum
spiexec(PG_FUNCTION_ARGS)
{
    int ret = 0, processed = 0;
    text *sql;

    SPI_connect();

    sql = PG_GETARG_TEXT_P(0);

    elog(INFO, "spiexec(): %s", text_to_cstring(sql));

    ret = SPI_exec(text_to_cstring(sql), 0);
    processed = SPI_processed;

    if (ret == SPI_OK_SELECT && SPI_processed > 0)
    {
        TupleDesc tupdesc = SPI_tuptable->tupdesc;
        SPITupleTable *tuptable = SPI_tuptable;
        char buf[8192];
        int i;

        for (ret = 0; ret < processed; ret++)
        {
            HeapTuple tuple = tuptable->vals[ret];

            for (i = 1, buf[0] = 0; i <= tupdesc->natts; i++)
                sprintf(buf + strlen (buf), " %s%s",
                        SPI_getvalue(tuple, tupdesc, i),
                        (i == tupdesc->natts) ? " " : " |");
            elog (INFO, "   %s", buf);
        }
    }

    SPI_finish();

    return processed;
}
#endif
