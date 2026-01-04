// https://github.com/TinyCC/examples/ex3.c

#include <stdlib.h>
#include <stdio.h>

int fib(int n) {
    if (n <= 2) {
        return 1;
    } else {
        return fib(n - 1) + fib(n - 2);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        return 1;
    }
    for (int i = 1; i < argc; i++) {
        int n = atoi(argv[i]);
        printf("fib(%d) = %d\n", n, fib(n));
    }
    return 0;
}
