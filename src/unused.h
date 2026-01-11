/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles special _ variable to suppress unused warnings.
 */

#pragma once

/* Transform _ identifier to unique unused variable name */
char *transpiler_transform_unused_identifier(void);

/* Reset the unused counter (for each translation unit) */
void transpiler_reset_unused_counter(void);
