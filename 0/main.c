#include "cz/standard.h"
#include "cz/extended.h"
#include "cz/types.h"
#include "cz/defer.h"
#include "cz/misc.h"

int main(void) {
    #ifdef __GNUC__
    fprintf(stdout, "GCC v%d.%d.%d\n", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
    #elifdef __llvm__
    fprintf(stdout, "Clang v%s\n", __llvm__);
    #endif

    byte b = 0x42;
    UNUSED(b);

    autofree int *i = malloc(sizeof(int));
    printf("%p = %d\n", i, *i);
    autofclose FILE *f = fopen("./README.md", "r");
    NOTHING();

    printf("%s:%d %s()\n", __FILE__, __LINE__, __FUNC__);

    return EXIT_SUCCESS;
}
