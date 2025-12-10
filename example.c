#include <stdint.h>
#include <stdio.h>

typedef struct Vec2 { int32_t x; int32_t y; } Vec2;

int32_t length(Vec2 *self) {
    return self->x*self->x + self->y*self->y;
}

int32_t main_main(void) {
    Vec2 v = {3,4};
    int32_t l = length(&v);
    printf("%d", l);
    return 0;
}

int main(void) { return main_main(); }
