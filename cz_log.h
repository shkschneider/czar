#ifndef CZ_LOG_H
#define CZ_LOG_H

// https://github.com/dmcrodrigues/macro-logger

#include <string.h>
#include <time.h>
#include <stdio.h>

static inline char *timenow() {
    static char buf[64];
    time_t tm;
    time(&tm);
    struct tm *ti;
    ti = localtime(&tm);
    strftime(buf, 64, "%Y-%m-%d %H:%M:%S", ti);
    return buf;
}

#define _LOG_LOG(lvl, file, line, format, ...) \
    fprintf(stderr, "%s [%s/%s:%d] " format "\n", timenow(), lvl, file, line, ## __VA_ARGS__)

#define LOG_DEBUG(format, ...) _LOG_LOG("DBG", __FILE__, __LINE__, format, ## __VA_ARGS__)
#define LOG_INFO(format, ...) _LOG_LOG("INF", __FILE__, __LINE__, format, ## __VA_ARGS__)
#define LOG_WARNING(format, ...) _LOG_LOG("WRN", __FILE__, __LINE__, format, ## __VA_ARGS__)
#define LOG_ERROR(format, ...) _LOG_LOG("ERR", __FILE__, __LINE__, format, ## __VA_ARGS__)

#endif
