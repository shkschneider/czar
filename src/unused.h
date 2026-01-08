/*
 * CZar - C semantic authority layer
 * Transpiler unused variable module (transpiler/unused.h)
 *
 * Handles special _ variable to suppress unused warnings.
 */

#pragma once

/* Transform _ identifier to unique unused variable name */
char *transpiler_transform_unused_identifier(void);

/* Reset the unused counter (for each translation unit) */
void transpiler_reset_unused_counter(void);
