#include "cz/standard.h"
#include "cz/extended.h"
#include "cz/types.h"
#include "cz/memory.h"
#include "cz/misc.h"
#include "cz/string.h"
#include "cz/case.h"
#include "cz/array.h" // single-list
#include "cz/list.h" // double-list
#include "cz/map.h" // hash-map (single-list)
#include "cz/log.h"

int main(void) {
    #ifdef __GNUC__
    LOG_DEBUG("GCC", "%d.%d.%d", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
    LOG_WARNING("GCC", "no Clang");
    #elifdef __llvm__
    LOG_DEBUG("Clang", "%s", __llvm__);
    LOG_WARNING("Clang", "no GCC");
    #endif

    byte b = 0x42;
    UNUSED(b);

    autofree int *i = malloc(sizeof(int));
    printf("%p = %d\n", (any*)i, *i);
    autofclose FILE *f = fopen("./README.md", "r");
    NOTHING();

    printf("%s:%d %s()\n", _FILE_, _LINE_, _FUNC_);

    printf("eq: %b\n", streq("42", "0"));
    printf("smth: %b\n", strsmth(""));
    printf("pre: '%b'\n", strpre("this is a test", "this"));
    printf("suf: '%b'\n", strsuf("this is a test", "test"));
    printf("err: %s\n", strerr());
    string s1 = " trimme ";
    printf("trm: '%s' '%s'\n", strtrmc(s1), strtrmc(""));
    printf("rpl: o->0 '%s'\n", strrpl(str("Hello, world!"), 'o', '0'));
    printf("drp: '%s'\n", strdrp(str("oHello, world!"), 'o'));

    printb((u8) 42);
    assert(((uintptr_t) malloc(1) & 0x0F) == 0);

    string s2 = str("upper");
    printf("upper: '%s'\n", case_upper(s2));
    printf("lower: '%s'\n", case_lower(s2));
    printf("title: '%s'\n", case_title(s2));
    string s3 = str(" sOmE WeIrD cAsE");
    string* ss = strdiv(s3, " ");
    for (int i = 0; ss[i]; i++) {
        printf("%d='%s' ", i, ss[i]);
    }
    printf("\n");
    free2(ss);
    printf("camel: '%s'\n", case_camel(s3));
    printf("pascal: '%s'\n", case_pascal(s3));
    printf("snake: '%s'\n", case_snake(s3));

    return EXIT_SUCCESS;
}
