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

#define _LOG_LOG(lvl, tag, format, ...) \
    fprintf(stderr, "%s [%s/%s] " format "\n", timenow(), lvl, tag, ## __VA_ARGS__)

#define LOG_DEBUG(tag, format, ...) _LOG_LOG("D", tag, format, ## __VA_ARGS__)
#define LOG_INFO(tag, format, ...) _LOG_LOG("I", tag, format, ## __VA_ARGS__)
#define LOG_WARNING(tag, format, ...) _LOG_LOG("W", tag, format, ## __VA_ARGS__)
#define LOG_ERROR(tag, format, ...) _LOG_LOG("E", tag, format, ## __VA_ARGS__)

#endif
