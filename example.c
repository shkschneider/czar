#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct Vec2 {
    int32_t x;
    int32_t y;
} Vec2;

int32_t length(Vec2* self)
{
    return ((self.x * self.x) + (self.y * self.y));
}

int32_t main_main()
{
    Vec2 v = (Vec2){ .x = 3, .y = 4 };
    const int32_t l = length((&v));
    ;
    return 0;
}

int main(void) { return main_main(); }

