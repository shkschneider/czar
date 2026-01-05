/*
 * CZar - C semantic authority layer  
 * Struct names tracking header (transpiler/struct_names.h)
 *
 * Tracks defined struct names for transformation.
 */

#pragma once

/* Add a struct name to the registry */
void struct_names_add(const char *name);

/* Check if a name is a registered struct and return the typedef name */
const char *struct_names_get_typedef(const char *name);

/* Clear all registered struct names */
void struct_names_clear(void);
