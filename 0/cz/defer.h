#ifndef CZ_DEFER_H_
#define CZ_DEFER_H_

// https://stackoverflow.com/a/69336439

#include <stdlib.h>
#define autofree __attribute__((cleanup(cz_auto_free)))
__attribute__ ((always_inline))
inline void cz_auto_free(void *ptr) {
    free(*(void **) ptr);
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

// https://fdiv.net/2015/10/08/emulating-defer-c-clang-or-gccblocks

#endif
