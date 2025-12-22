// compile: gcc -Wall -O2 -o coro_demo coro_demo.c
// run: ./coro_demo

#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <stdlib.h>
#include <ucontext.h>

#define STACK_SIZE (64*1024)

ucontext_t sched_ctx;   // scheduler / main context
ucontext_t coro1_ctx;
ucontext_t coro2_ctx;

char *stack1;
char *stack2;

/* coroutine functions must take (void) and return void */
void coro1_func(void) {
    printf("coro1: start\n");
    // yield to scheduler
    swapcontext(&coro1_ctx, &sched_ctx);
    printf("coro1: resumed\n");
    swapcontext(&coro1_ctx, &sched_ctx);
    printf("coro1: exiting\n");
    // returning will resume uc_link if set (or exit if NULL)
}

void coro2_func(void) {
    printf("coro2: start\n");
    swapcontext(&coro2_ctx, &sched_ctx);
    printf("coro2: resumed\n");
    swapcontext(&coro2_ctx, &sched_ctx);
    printf("coro2: exiting\n");
}

int main(void) {
    /* allocate stacks */
    stack1 = malloc(STACK_SIZE);
    stack2 = malloc(STACK_SIZE);
    if (!stack1 || !stack2) {
        perror("malloc");
        return 1;
    }

    /* initialize contexts */
    getcontext(&coro1_ctx);
    coro1_ctx.uc_stack.ss_sp = stack1;
    coro1_ctx.uc_stack.ss_size = STACK_SIZE;
    coro1_ctx.uc_link = &sched_ctx;            // where to resume when coro exits
    makecontext(&coro1_ctx, coro1_func, 0);

    getcontext(&coro2_ctx);
    coro2_ctx.uc_stack.ss_sp = stack2;
    coro2_ctx.uc_stack.ss_size = STACK_SIZE;
    coro2_ctx.uc_link = &sched_ctx;
    makecontext(&coro2_ctx, coro2_func, 0);

    printf("main: start scheduling\n");

    // start coro1
    swapcontext(&sched_ctx, &coro1_ctx); // saves sched_ctx, switches to coro1
    printf("main: returned from coro1 (1)\n");

    // start coro2
    swapcontext(&sched_ctx, &coro2_ctx);
    printf("main: returned from coro2 (1)\n");

    // resume coro1
    swapcontext(&sched_ctx, &coro1_ctx);
    printf("main: returned from coro1 (2)\n");

    // resume coro2
    swapcontext(&sched_ctx, &coro2_ctx);
    printf("main: returned from coro2 (2)\n");

    printf("main: done\n");

    free(stack1);
    free(stack2);
    return 0;
}
