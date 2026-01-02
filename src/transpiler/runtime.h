/*
 * CZar - C semantic authority layer
 * Transpiler runtime module (transpiler/runtime.h)
 *
 * Handles CZar runtime macro definitions for transpilation.
 */

#ifndef TRANSPILER_RUNTIME_H
#define TRANSPILER_RUNTIME_H

/* Get the runtime macro definitions to inject into transpiled code */
const char *transpiler_get_runtime_macros(void);

#endif /* TRANSPILER_RUNTIME_H */
