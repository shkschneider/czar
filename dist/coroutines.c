// coroutines.c - Proof of Concept for coroutines using makecontext/swapcontext
// This demonstrates the basic coroutine functionality that will be implemented
// in the Czar standard library.

#include <stdio.h>
#include <stdlib.h>
#include <ucontext.h>
#include <stdbool.h>

#define STACK_SIZE 8192

// Coroutine state
typedef enum {
    CO_READY,    // Created but not started
    CO_RUNNING,  // Currently executing
    CO_SUSPENDED,// Yielded, waiting to be resumed
    CO_DEAD      // Finished execution
} co_state_t;

// Coroutine structure
typedef struct {
    ucontext_t context;      // Coroutine execution context
    ucontext_t *caller;      // Context to return to
    void *stack;             // Stack memory
    size_t stack_size;       // Stack size
    co_state_t state;        // Current state
    void (*func)(void);      // Function to execute
    int yield_value;         // Value yielded/returned
} coroutine_t;

// Global pointer to current coroutine (for yield)
static coroutine_t *current_co = NULL;

// Create a new coroutine
coroutine_t* co_create(void (*func)(void)) {
    coroutine_t *co = (coroutine_t*)malloc(sizeof(coroutine_t));
    if (!co) return NULL;
    
    co->stack = malloc(STACK_SIZE);
    if (!co->stack) {
        free(co);
        return NULL;
    }
    
    co->stack_size = STACK_SIZE;
    co->state = CO_READY;
    co->func = func;
    co->yield_value = 0;
    co->caller = NULL;
    
    return co;
}

// Free coroutine resources
void co_free(coroutine_t *co) {
    if (co) {
        if (co->stack) free(co->stack);
        free(co);
    }
}

// Wrapper function that runs the coroutine
static void co_wrapper(void) {
    if (current_co && current_co->func) {
        current_co->func();
    }
    // When function completes, mark as dead
    if (current_co) {
        current_co->state = CO_DEAD;
    }
}

// Yield from coroutine with a value
void co_yield(int value) {
    if (!current_co || !current_co->caller) return;
    
    current_co->yield_value = value;
    current_co->state = CO_SUSPENDED;
    
    // Save current context and switch back to caller
    swapcontext(&current_co->context, current_co->caller);
}

// Resume/start a coroutine
int co_resume(coroutine_t *co) {
    if (!co) return -1;
    
    ucontext_t caller_context;
    co->caller = &caller_context;
    current_co = co;
    
    if (co->state == CO_READY) {
        // First time running - initialize context
        if (getcontext(&co->context) == -1) {
            return -1;
        }
        
        co->context.uc_stack.ss_sp = co->stack;
        co->context.uc_stack.ss_size = co->stack_size;
        co->context.uc_link = &caller_context; // Return here when done
        
        makecontext(&co->context, co_wrapper, 0);
        co->state = CO_RUNNING;
        
        // Switch to coroutine
        swapcontext(&caller_context, &co->context);
    } else if (co->state == CO_SUSPENDED) {
        // Resume from yield
        co->state = CO_RUNNING;
        swapcontext(&caller_context, &co->context);
    }
    
    return co->yield_value;
}

// Check if coroutine is dead
bool co_is_dead(coroutine_t *co) {
    return co && co->state == CO_DEAD;
}

// Example counter function that yields values
void counter() {
    for (unsigned char c = 0; c < 123; c++) {
        co_yield(c + 1);
    }
}

// Example fibonacci function
void fibonacci() {
    int a = 0, b = 1;
    for (int i = 0; i < 10; i++) {
        co_yield(a);
        int temp = a + b;
        a = b;
        b = temp;
    }
}

// Main test program
int main() {
    printf("=== Coroutines POC ===\n\n");
    
    // Test 1: Two counter coroutines running independently
    printf("Test 1: Two independent counters\n");
    coroutine_t *co1 = co_create(counter);
    coroutine_t *co2 = co_create(counter);
    
    printf("Coroutines launched\n");
    
    // Alternate between two coroutines
    for (int i = 0; i < 5; i++) {
        int val1 = co_resume(co1);
        int val2 = co_resume(co2);
        printf("co1: %d, co2: %d\n", val1, val2);
    }
    
    co_free(co1);
    co_free(co2);
    
    // Test 2: Fibonacci coroutine
    printf("\nTest 2: Fibonacci sequence\n");
    coroutine_t *fib = co_create(fibonacci);
    
    while (!co_is_dead(fib)) {
        int val = co_resume(fib);
        if (!co_is_dead(fib) || val != 0) {
            printf("%d ", val);
        }
    }
    printf("\n");
    
    co_free(fib);
    
    // Test 3: Run counter to completion
    printf("\nTest 3: Counter from 1 to 10\n");
    coroutine_t *co3 = co_create(counter);
    
    for (int i = 0; i < 10; i++) {
        int val = co_resume(co3);
        printf("%d ", val);
    }
    printf("\n");
    
    co_free(co3);
    
    printf("\n=== POC Complete ===\n");
    return 0;
}
