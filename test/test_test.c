#include <stdlib.h>
#include <string.h>

#include "cz_case.h"
#include "cz_test.h"

int main(void) {
    char *s = malloc(sizeof(char) * (strlen("hello world") + 1));
    strcpy(s, "hello world");
    s = case_upper(s);
    TEST(s, "HELLO WORLD");
    s = case_lower(s);
    TEST(s, "hello world");
    s = case_title(s);
    TEST(s, "Hello world");
    s = case_pascal(s);
    TEST(s, "HelloWorld");
    strcpy(s, "hello_world");
    s = case_camel(s);
    TEST(s, "helloWorld");
    strcpy(s, "hello world");
    s = case_snake(s);
    TEST(s, "hello_world");
    free(s);
    return 0;
}
