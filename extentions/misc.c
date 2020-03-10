#include <time.h>
#include <stdio.h>

#include "misc.h"

void
time_to_str(time_t rawtime, char *time_str, int time_len)
{
    struct tm* ptm = localtime(&rawtime);

    if (ptm == NULL)
    {
        fputs("time_to_str(): The localtime() function failed", stderr);
        return;
    }

    strftime(time_str, time_len, "%d.%m.%Y %H:%M:%S", ptm);
}

void
time_str_now(char *time_buf_str, int time_buf_len)
{
    time_t rawtime;

    rawtime = time(NULL);

    if (rawtime == -1)
    {
        fputs("The time() function failed", stderr);
        return;
    }

    time_to_str(rawtime, time_buf_str, time_buf_len);
}
