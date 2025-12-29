// co.h - Coroutine support for Czar language
// Provides coroutines using makecontext/swapcontext/getcontext/setcontext
// Part of the Czar standard library

#ifndef CZ_CO_H
#define CZ_CO_H

#include <stdlib.h>
#include <ucontext.h>
#include <stdbool.h>
#include <stdint.h>

#define CZ_CO_STACK_SIZE 8192

// Coroutine state
typedef enum {
    CZ_CO_READY,     // Created but not started
    CZ_CO_RUNNING,   // Currently executing
    CZ_CO_SUSPENDED, // Yielded, waiting to be resumed
    CZ_CO_DEAD       // Finished execution
} cz_co_state_t;

// Coroutine structure
typedef struct cz_coroutine {
    ucontext_t context;         // Coroutine execution context
    ucontext_t caller_context;  // Context to return to
    void *stack;                // Stack memory
    size_t stack_size;          // Stack size
    cz_co_state_t state;        // Current state
    void (*func)(void);         // Function to execute
    int32_t yield_value;        // Value yielded/returned
    bool has_value;             // Whether a value was yielded
} cz_coroutine;

// Global pointer to current coroutine (for yield)
static cz_coroutine *_cz_current_co = NULL;

// Initialize a coroutine structure
static inline cz_coroutine* _cz_co_init(void (*func)(void)) {
    cz_coroutine *co = (cz_coroutine*)malloc(sizeof(cz_coroutine));
    if (!co) return NULL;
    
    // Use calloc to zero the stack for security
    co->stack = calloc(1, CZ_CO_STACK_SIZE);
    if (!co->stack) {
        free(co);
        return NULL;
    }
    
    co->stack_size = CZ_CO_STACK_SIZE;
    co->state = CZ_CO_READY;
    co->func = func;
    co->yield_value = 0;
    co->has_value = false;
    
    return co;
}

// Free coroutine resources
static inline void _cz_co_free(cz_coroutine *co) {
    if (co) {
        if (co->stack) free(co->stack);
        free(co);
    }
}

// Wrapper function that runs the coroutine
static void _cz_co_wrapper(void) {
    if (_cz_current_co && _cz_current_co->func) {
        _cz_current_co->func();
    }
    // When function completes, mark as dead
    if (_cz_current_co) {
        _cz_current_co->state = CZ_CO_DEAD;
    }
}

// Yield from coroutine with a value
static inline void _cz_co_yield(int32_t value) {
    if (!_cz_current_co) return;
    
    _cz_current_co->yield_value = value;
    _cz_current_co->has_value = true;
    _cz_current_co->state = CZ_CO_SUSPENDED;
    
    // Save current context and switch back to caller
    swapcontext(&_cz_current_co->context, &_cz_current_co->caller_context);
}

// Resume/start a coroutine
static inline int32_t _cz_co_resume(cz_coroutine *co) {
    if (!co) return 0;
    
    cz_coroutine *prev_co = _cz_current_co;
    _cz_current_co = co;
    co->has_value = false;
    
    if (co->state == CZ_CO_READY) {
        // First time running - initialize context
        if (getcontext(&co->context) == -1) {
            _cz_current_co = prev_co;
            return 0;
        }
        
        co->context.uc_stack.ss_sp = co->stack;
        co->context.uc_stack.ss_size = co->stack_size;
        co->context.uc_link = &co->caller_context; // Return here when done
        
        makecontext(&co->context, _cz_co_wrapper, 0);
        co->state = CZ_CO_RUNNING;
        
        // Switch to coroutine
        swapcontext(&co->caller_context, &co->context);
    } else if (co->state == CZ_CO_SUSPENDED) {
        // Resume from yield
        co->state = CZ_CO_RUNNING;
        swapcontext(&co->caller_context, &co->context);
    }
    
    _cz_current_co = prev_co;
    return co->yield_value;
}

// Check if coroutine is dead
static inline bool _cz_co_is_dead(cz_coroutine *co) {
    return co && co->state == CZ_CO_DEAD;
}

// Check if coroutine is ready
static inline bool _cz_co_is_ready(cz_coroutine *co) {
    return co && co->state == CZ_CO_READY;
}

// Check if coroutine is running
static inline bool _cz_co_is_running(cz_coroutine *co) {
    return co && co->state == CZ_CO_RUNNING;
}

// Check if coroutine is suspended
static inline bool _cz_co_is_suspended(cz_coroutine *co) {
    return co && co->state == CZ_CO_SUSPENDED;
}

// Get coroutine state
static inline int32_t _cz_co_state(cz_coroutine *co) {
    if (!co) return -1;
    return (int32_t)co->state;
}

#endif // CZ_CO_H
