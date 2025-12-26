#include <stdio.h>

int main() {
    int n = 999;
    int i;
    int t1 = 0, t2 = 1;
    int nextTerm = t1 + t2;
    // print the first two terms t1 and t2
    printf("Fibonacci Series: %d, %d, ", t1, t2);
    // print 3rd to nth terms
    for (i = 3; i <= n; ++i) {
        printf("fib(%d/%d) = %d\n", i, n, nextTerm);
        t1 = t2;
        t2 = nextTerm;
        nextTerm = t1 + t2;
    }
    return 0;
}
