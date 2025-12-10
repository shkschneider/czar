#include <stdlib.h>
#include <string.h>

#include "cz_string.h"
#include "cz_memory.h"
#include "cz_test.h"

int main(void) {
    // Test str (strdup wrapper)
    string s1 = str("hello");
    TEST(s1, "hello");
    free(s1);

    // Test streq
    assert(streq("test", "test") == true);
    assert(streq("test", "other") == false);
    assert(streq(NULL, NULL) == true);
    assert(streq("test", NULL) == false);
    assert(streq(NULL, "test") == false);

    // Test strsmth (string has something)
    assert(strsmth("test") == true);
    assert(strsmth("") == false);
    assert(strsmth(NULL) == false);

    // Test strpre (prefix)
    assert(strpre("hello world", "hello") == true);
    assert(strpre("hello world", "world") == false);
    assert(strpre(NULL, NULL) == true);
    assert(strpre("test", NULL) == true);
    assert(strpre(NULL, "test") == false);

    // Test strsuf (suffix)
    assert(strsuf("hello world", "world") == true);
    assert(strsuf("hello world", "hello") == false);
    assert(strsuf(NULL, NULL) == true);
    assert(strsuf("test", NULL) == true);
    assert(strsuf(NULL, "test") == false);

    // Test strtrmc (trim)
    string s2 = strtrmc("  hello world  ");
    TEST(s2, "hello world");
    free(s2);

    string s3 = strtrmc("hello world");
    TEST(s3, "hello world");
    free(s3);

    // Test strdiv (split)
    string* parts = strdiv("hello,world,test", ",");
    TEST(parts[0], "hello");
    TEST(parts[1], "world");
    TEST(parts[2], "test");
    assert(parts[3] == NULL);
    free2(parts);

    // Test strrpl (replace char)
    char* s4 = strdup("hello world");
    strrpl(s4, 'o', 'x');
    TEST(s4, "hellx wxrld");
    free(s4);

    // Test strdrp (drop char)
    string s5 = strdrp("hello world", 'o');
    TEST(s5, "hell wrld");
    free(s5);

    string s6 = strdrp("aaa", 'a');
    TEST(s6, "");
    free(s6);

    string s7 = strdrp("ababa", 'a');
    TEST(s7, "bb");
    free(s7);

    return 0;
}
