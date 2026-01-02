/*
 * CZar - C semantic authority layer
 * Transpiler unused variable module (transpiler/unused.h)
 *
 * Handles special _ variable to suppress unused warnings.
 */

#ifndef TRANSPILER_UNUSED_H
#define TRANSPILER_UNUSED_H

/* Transform _ identifier to unique unused variable name */
char *transpiler_transform_unused_identifier(void);

/* Reset the unused counter (for each translation unit) */
void transpiler_reset_unused_counter(void);

#endif /* TRANSPILER_UNUSED_H */
