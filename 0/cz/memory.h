#ifndef CZ_MEMORY_H
#define CZ_MEMORY_H

// https://fdiv.net/2015/10/08/emulating-defer-c-clang-or-gccblocks
// https://stackoverflow.com/a/69336439

#include <stdlib.h>
#define autofree __attribute__((cleanup(cz_auto_free)))
__attribute__ ((always_inline))
inline void cz_auto_free(void* ptr) {
    free(*(void**) ptr);
}

#include <unistd.h>
#define autoclose __attribute__((cleanup(cz_auto_close)))
__attribute__ ((always_inline))
inline void cz_auto_close(int fd) {
    close(fd);
}

#include <stdio.h>
#define autofclose __attribute__((cleanup(cz_auto_fclose)))
__attribute__ ((always_inline))
inline void cz_auto_fclose(FILE **file) {
    fclose(*file);
}

#define free1(p) free(p)
#define free2(p) \
    for (unsigned int i = 0; p[i]; i++) { \
        free(p[i]); \
    } \
    free(p);

#endif
