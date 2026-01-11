/*
 * CZar - semantic authority layer for C
 * MIT License Copyright (c) 2026 ShkSchneider
 * https://github.com/shkschneider/czar
 *
 * Handles automatic typedef generation for named structs.
 * Transforms: struct Name { ... }; into typedef struct Name_s { ... } Name_t;
 * Replaces all uses of Name with Name_t in generated C code.
 * Methods use the base name: Name_method (not Name_t_method)
 */

#include "cz.h"
#include "structs.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>

/* Maximum struct name lengths */
#define MAX_STRUCT_NAME_LEN 509  /* Leave room for "_t" suffix and null terminator */
#define MAX_TYPEDEF_NAME_LEN 512 /* MAX_STRUCT_NAME_LEN + "_t" (2) + null (1) */
#define MAX_PATH_LEN 600

/* Maximum number of struct names we can track */
#define MAX_STRUCT_NAMES 256

/* Tracked struct names */
typedef struct {
    char *original_name;  /* e.g., "Vec2" */
    char *typedef_name;   /* e.g., "Vec2_t" */
} StructNameMapping;

static StructNameMapping struct_name_mappings[MAX_STRUCT_NAMES];
static size_t struct_name_count = 0;

/* Track a struct name mapping */
static void track_struct_name(const char *original, const char *typedef_name) {
    if (struct_name_count >= MAX_STRUCT_NAMES) {
        return;
    }
    
    /* Check if already tracked */
    for (size_t i = 0; i < struct_name_count; i++) {
        if (struct_name_mappings[i].original_name &&
            strcmp(struct_name_mappings[i].original_name, original) == 0) {
            return;
        }
    }
    
    char *orig_copy = strdup(original);
    char *typedef_copy = strdup(typedef_name);
    if (!orig_copy || !typedef_copy) {
        free(orig_copy);
        free(typedef_copy);
        return;
    }
    
    struct_name_mappings[struct_name_count].original_name = orig_copy;
    struct_name_mappings[struct_name_count].typedef_name = typedef_copy;
    struct_name_count++;
}

/* Get typedef name for a struct (returns NULL if not tracked) */
static const char* get_typedef_name(const char *original) {
    for (size_t i = 0; i < struct_name_count; i++) {
        if (struct_name_mappings[i].original_name &&
            strcmp(struct_name_mappings[i].original_name, original) == 0) {
            return struct_name_mappings[i].typedef_name;
        }
    }
    return NULL;
}

/* Transform named struct declarations into typedef structs */
void transpiler_transform_structs(ASTNode_t *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: struct identifier { ... }; */
    /* Transform to: typedef struct { ... } identifier; */

    for (size_t i = 0; i < ast->child_count; i++) {
        /* Need at least: struct, whitespace, identifier, whitespace, { */
        if (i + 4 >= ast->child_count) {
            continue;
        }

        ASTNode_t *n1 = ast->children[i];
        ASTNode_t *n2 = ast->children[i + 1];
        ASTNode_t *n3 = ast->children[i + 2];

        if (n1->type != AST_TOKEN || n2->type != AST_TOKEN || n3->type != AST_TOKEN) {
            continue;
        }

        Token *t1 = &n1->token;
        Token *t2 = &n2->token;
        Token *t3 = &n3->token;

        /* Check for: struct <whitespace> identifier */
        if (t1->type == TOKEN_IDENTIFIER && t1->text && strcmp(t1->text, "struct") == 0 &&
            t2->type == TOKEN_WHITESPACE &&
            t3->type == TOKEN_IDENTIFIER) {

            /* Look ahead to find the opening brace { - it should be immediately after the struct name */
            /* Pattern: struct Name { (with optional whitespace) */
            /* We want to reject: struct Name x = { (variable declaration) */
            size_t brace_idx = 0;
            int found_brace = 0;
            int found_other = 0;
            for (size_t j = i + 3; j < ast->child_count && j < i + 10; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_WHITESPACE || tj->type == TOKEN_COMMENT) {
                        continue; /* Skip whitespace and comments */
                    }
                    if (tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, "{") == 0) {
                        brace_idx = j;
                        found_brace = 1;
                        break;
                    }
                    /* If we find anything else (identifier, =, etc), this is not a struct definition */
                    found_other = 1;
                    break;
                }
            }

            if (!found_brace || found_other) {
                continue; /* Not a struct definition */
            }

            /* Find the closing brace and semicolon */
            int brace_depth = 0;
            size_t closing_brace_idx = 0;
            for (size_t j = brace_idx; j < ast->child_count; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_PUNCTUATION) {
                        if (tj->text && strcmp(tj->text, "{") == 0) {
                            brace_depth++;
                        } else if (tj->text && strcmp(tj->text, "}") == 0) {
                            brace_depth--;
                            if (brace_depth == 0) {
                                closing_brace_idx = j;
                                break;
                            }
                        }
                    }
                }
            }

            if (closing_brace_idx == 0) {
                continue; /* Couldn't find matching closing brace */
            }

            /* Now we have a valid struct definition from i to closing_brace_idx */
            /* Transform: struct Name { ... } to typedef struct Name { ... } Name */
            /* This allows users to use Name directly in CZar code */

            /* Step 1: Save the struct name (t3->text) */
            char *struct_name = strdup(t3->text);
            if (!struct_name) {
                continue; /* Memory allocation failed */
            }

            /* Step 2: Replace "struct" with "typedef struct" */
            char *new_text = strdup("typedef struct");
            if (!new_text) {
                free(struct_name);
                continue; /* Memory allocation failed */
            }
            free(t1->text);
            t1->text = new_text;
            t1->length = strlen(new_text);

            /* Step 3: Modify the struct name to add _s suffix */
            /* Change "struct Name" to "struct Name_s" */
            size_t struct_name_len = strlen(struct_name);
            char *struct_tag_name = malloc(struct_name_len + 3); /* +2 for "_s" + 1 for null */
            if (!struct_tag_name) {
                free(struct_name);
                continue;
            }
            snprintf(struct_tag_name, struct_name_len + 3, "%s_s", struct_name);
            
            free(t3->text);
            t3->text = struct_tag_name;
            t3->length = strlen(struct_tag_name);

            /* Step 4: After the closing brace, add the typedef name */
            /* Look for whitespace and semicolon after closing brace */
            size_t semicolon_idx = 0;
            for (size_t j = closing_brace_idx + 1; j < ast->child_count && j < closing_brace_idx + 5; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_PUNCTUATION && tj->text && strcmp(tj->text, ";") == 0) {
                        semicolon_idx = j;
                        break;
                    }
                }
            }

            if (semicolon_idx > 0) {
                /* Insert the typedef name before the semicolon */
                size_t insert_pos = semicolon_idx;

                /* Use Name_t for typedef instead of Name */
                char *typedef_name = malloc(struct_name_len + 3); /* +2 for "_t" + 1 for null */
                if (!typedef_name) {
                    free(struct_name);
                    continue;
                }
                snprintf(typedef_name, struct_name_len + 3, "%s_t", struct_name);
                
                /* Track the mapping: Name -> Name_t */
                track_struct_name(struct_name, typedef_name);

                /* We need to insert: " Name" before the semicolon */
                /* Create a new token for the space */
                ASTNode_t *space_node = malloc(sizeof(ASTNode_t));
                if (space_node) {
                    space_node->type = AST_TOKEN;
                    space_node->token.type = TOKEN_WHITESPACE;
                    space_node->token.text = strdup(" ");
                    space_node->token.length = 1;
                    space_node->token.line = t1->line;
                    space_node->token.column = 0;
                    space_node->children = NULL;
                    space_node->child_count = 0;
                    space_node->child_capacity = 0;
                }

                /* Create a new token for the typedef name (Name_t) */
                ASTNode_t *name_node = malloc(sizeof(ASTNode_t));
                if (name_node) {
                    name_node->type = AST_TOKEN;
                    name_node->token.type = TOKEN_IDENTIFIER;
                    name_node->token.text = typedef_name; /* Transfer ownership */
                    name_node->token.length = strlen(typedef_name);
                    name_node->token.line = t1->line;
                    name_node->token.column = 0;
                    name_node->children = NULL;
                    name_node->child_count = 0;
                    name_node->child_capacity = 0;

                    /* Insert the nodes before the semicolon */
                    /* We need to grow the children array and shift elements */
                    size_t new_count = ast->child_count + 2;
                    if (new_count > ast->child_capacity) {
                        size_t new_capacity = new_count * 2;
                        ASTNode_t **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode_t *));
                        if (new_children) {
                            ast->children = new_children;
                            ast->child_capacity = new_capacity;
                        } else {
                            /* Memory allocation failed, clean up */
                            free(space_node);
                            free(name_node);
                            free(struct_name);
                            continue;
                        }
                    }

                    /* Shift elements to make room */
                    for (size_t j = ast->child_count; j > insert_pos; j--) {
                        ast->children[j + 1] = ast->children[j - 1];
                    }

                    /* Insert the new nodes */
                    ast->children[insert_pos] = space_node;
                    ast->children[insert_pos + 1] = name_node;
                    ast->child_count += 2;

                    /* Skip ahead so we don't process this struct again */
                    i = semicolon_idx + 2;

                    /* Free struct_name */
                    free(struct_name);
                } else {
                    free(struct_name);
                    free(typedef_name);
                    if (space_node) free(space_node);
                }
            } else {
                free(struct_name);
            }
        }
    }
}

/* Transform struct initialization syntax
 * Handles:
 * - MyStruct s = {} -> MyStruct s = {0}
 * - MyStruct s = MyStruct {} -> MyStruct s = {0}
 * - MyStruct s = MyStruct {0} -> MyStruct s = {0}
 */
void transpiler_transform_struct_init(ASTNode_t *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }

    /* Look for pattern: = { or = StructName { */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (i + 2 >= ast->child_count) {
            continue;
        }

        ASTNode_t *n1 = ast->children[i];
        if (n1->type != AST_TOKEN || n1->token.type != TOKEN_OPERATOR ||
            !n1->token.text || strcmp(n1->token.text, "=") != 0) {
            continue;
        }

        /* Found =, now look for what comes after (skipping whitespace) */
        size_t next_idx = i + 1;
        while (next_idx < ast->child_count &&
               ast->children[next_idx]->type == AST_TOKEN &&
               ast->children[next_idx]->token.type == TOKEN_WHITESPACE) {
            next_idx++;
        }

        if (next_idx >= ast->child_count) {
            continue;
        }

        ASTNode_t *next = ast->children[next_idx];
        if (next->type != AST_TOKEN) {
            continue;
        }

        /* Case 1: = {} (empty braces) */
        if (next->token.type == TOKEN_PUNCTUATION && next->token.text &&
            strcmp(next->token.text, "{") == 0) {
            /* Check if followed by } */
            size_t close_idx = next_idx + 1;
            while (close_idx < ast->child_count &&
                   ast->children[close_idx]->type == AST_TOKEN &&
                   ast->children[close_idx]->token.type == TOKEN_WHITESPACE) {
                close_idx++;
            }

            if (close_idx < ast->child_count &&
                ast->children[close_idx]->type == AST_TOKEN &&
                ast->children[close_idx]->token.type == TOKEN_PUNCTUATION &&
                ast->children[close_idx]->token.text &&
                strcmp(ast->children[close_idx]->token.text, "}") == 0) {
                /* Insert 0 between { and } */
                ASTNode_t *zero_node = malloc(sizeof(ASTNode_t));
                if (zero_node) {
                    zero_node->type = AST_TOKEN;
                    zero_node->token.type = TOKEN_NUMBER;
                    zero_node->token.text = strdup("0");
                    zero_node->token.length = 1;
                    zero_node->token.line = next->token.line;
                    zero_node->token.column = 0;
                    zero_node->children = NULL;
                    zero_node->child_count = 0;
                    zero_node->child_capacity = 0;

                    if (zero_node->token.text) {
                        /* Insert zero_node between { and } */
                        size_t insert_pos = next_idx + 1;
                        size_t new_count = ast->child_count + 1;

                        if (new_count > ast->child_capacity) {
                            size_t new_capacity = new_count * 2;
                            ASTNode_t **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode_t *));
                            if (new_children) {
                                ast->children = new_children;
                                ast->child_capacity = new_capacity;
                            } else {
                                free(zero_node->token.text);
                                free(zero_node);
                                continue;
                            }
                        }

                        /* Shift elements */
                        for (size_t j = ast->child_count; j > insert_pos; j--) {
                            ast->children[j] = ast->children[j - 1];
                        }

                        ast->children[insert_pos] = zero_node;
                        ast->child_count++;
                    } else {
                        free(zero_node);
                    }
                }
            }
        }
        /* Case 2: = StructName { ... } */
        else if (next->token.type == TOKEN_IDENTIFIER) {
            /* Look for { after the identifier */
            size_t brace_idx = next_idx + 1;
            while (brace_idx < ast->child_count &&
                   ast->children[brace_idx]->type == AST_TOKEN &&
                   ast->children[brace_idx]->token.type == TOKEN_WHITESPACE) {
                brace_idx++;
            }

            if (brace_idx < ast->child_count &&
                ast->children[brace_idx]->type == AST_TOKEN &&
                ast->children[brace_idx]->token.type == TOKEN_PUNCTUATION &&
                ast->children[brace_idx]->token.text &&
                strcmp(ast->children[brace_idx]->token.text, "{") == 0) {

                /* This is StructName { ... } pattern */
                /* Check what's inside the braces */
                size_t inside_idx = brace_idx + 1;
                while (inside_idx < ast->child_count &&
                       ast->children[inside_idx]->type == AST_TOKEN &&
                       ast->children[inside_idx]->token.type == TOKEN_WHITESPACE) {
                    inside_idx++;
                }

                /* Check if empty */
                int is_empty = 0;

                if (inside_idx < ast->child_count &&
                    ast->children[inside_idx]->type == AST_TOKEN) {
                    if (ast->children[inside_idx]->token.type == TOKEN_PUNCTUATION &&
                        ast->children[inside_idx]->token.text &&
                        strcmp(ast->children[inside_idx]->token.text, "}") == 0) {
                        is_empty = 1;
                    }
                }

                /* Transform by removing the struct name */
                /* = StructName { -> = { */
                free(next->token.text);
                next->token.text = strdup("");
                next->token.length = 0;

                /* If empty, add 0 */
                if (is_empty) {

                    ASTNode_t *zero_node = malloc(sizeof(ASTNode_t));
                    if (zero_node) {
                        zero_node->type = AST_TOKEN;
                        zero_node->token.type = TOKEN_NUMBER;
                        zero_node->token.text = strdup("0");
                        zero_node->token.length = 1;
                        zero_node->token.line = ast->children[brace_idx]->token.line;
                        zero_node->token.column = 0;
                        zero_node->children = NULL;
                        zero_node->child_count = 0;
                        zero_node->child_capacity = 0;

                        if (zero_node->token.text) {
                            /* Insert before } */
                            size_t insert_pos = brace_idx + 1;
                            size_t new_count = ast->child_count + 1;

                            if (new_count > ast->child_capacity) {
                                size_t new_capacity = new_count * 2;
                                ASTNode_t **new_children = realloc(ast->children, new_capacity * sizeof(ASTNode_t *));
                                if (new_children) {
                                    ast->children = new_children;
                                    ast->child_capacity = new_capacity;
                                } else {
                                    free(zero_node->token.text);
                                    free(zero_node);
                                    continue;
                                }
                            }

                            /* Shift elements */
                            for (size_t j = ast->child_count; j > insert_pos; j--) {
                                ast->children[j] = ast->children[j - 1];
                            }

                            ast->children[insert_pos] = zero_node;
                            ast->child_count++;
                        } else {
                            free(zero_node);
                        }
                    }
                }
            }
        }
    }
}

/* Parse a .cz.h header file to extract typedef struct patterns
 * Returns 1 on success, 0 on failure
 */
static int parse_header_for_typedefs(const char *source_filename, const char *header_path) {
    /* Construct full path to header file */
    char full_path[1024];
    const char *last_slash = strrchr(source_filename, '/');
    if (last_slash) {
        size_t dir_len = last_slash - source_filename + 1;
        if (dir_len + strlen(header_path) + 1 > sizeof(full_path)) {
            return 0;
        }
        memcpy(full_path, source_filename, dir_len);
        strcpy(full_path + dir_len, header_path);
    } else {
        if (strlen(header_path) + 1 > sizeof(full_path)) {
            return 0;
        }
        strcpy(full_path, header_path);
    }
    
    /* Try to open the header file */
    FILE *f = fopen(full_path, "r");
    if (!f) {
        return 0;
    }
    
    /* Read the file content */
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if (file_size <= 0 || file_size > 1024 * 1024) { /* Max 1MB */
        fclose(f);
        return 0;
    }
    
    char *content = malloc(file_size + 1);
    if (!content) {
        fclose(f);
        return 0;
    }
    
    size_t read_size = fread(content, 1, file_size, f);
    fclose(f);
    content[read_size] = '\0';
    
    /* Simple regex-like scan for: typedef struct Name_s { ... } Name_t; */
    /* We look for "typedef struct <name>_s" followed eventually by "} <name>_t;" */
    char *p = content;
    while ((p = strstr(p, "typedef struct ")) != NULL) {
        p += 15; /* Skip "typedef struct " */
        
        /* Extract struct tag name */
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        
        char *tag_start = p;
        while (*p && (isalnum(*p) || *p == '_')) p++;
        if (p == tag_start) continue;
        
        size_t tag_len = p - tag_start;
        if (tag_len < 3) continue; /* Need at least X_s */
        
        /* Check if ends with _s */
        if (tag_start[tag_len - 2] != '_' || tag_start[tag_len - 1] != 's') {
            continue;
        }
        
        /* Extract base name (without _s) */
        char base_name[MAX_STRUCT_NAME_LEN];
        if (tag_len - 2 >= sizeof(base_name)) continue;
        memcpy(base_name, tag_start, tag_len - 2);
        base_name[tag_len - 2] = '\0';
        
        /* Find the closing brace and typedef name */
        /* Look for "} Name_t;" */
        char *typedef_pattern = malloc(tag_len + 10); /* "} " + base + "_t;" */
        if (!typedef_pattern) continue;
        sprintf(typedef_pattern, "} %s_t", base_name);
        
        char *typedef_loc = strstr(p, typedef_pattern);
        if (typedef_loc) {
            /* Found a match - track this mapping */
            char typedef_name[MAX_TYPEDEF_NAME_LEN];
            snprintf(typedef_name, sizeof(typedef_name), "%s_t", base_name);
            track_struct_name(base_name, typedef_name);
        }
        
        free(typedef_pattern);
    }
    
    free(content);
    return 1;
}

/* Scan the AST for #import directives and parse the corresponding .cz.h files
 * to extract typedef information
 */
static void scan_imports_for_typedefs(ASTNode_t *ast, const char *source_filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT || !source_filename) {
        return;
    }
    
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            continue;
        }
        
        Token *t = &ast->children[i]->token;
        
        /* Look for #import directives */
        if (t->type == TOKEN_PREPROCESSOR && t->text &&
            t->length >= 7 && strncmp(t->text, "#import", 7) == 0) {
            
            /* Extract the module path from #import "path" */
            const char *quote_start = strchr(t->text, '"');
            if (!quote_start) continue;
            
            const char *quote_end = strchr(quote_start + 1, '"');
            if (!quote_end) continue;
            
            size_t path_len = quote_end - quote_start - 1;
            char module_path[512];
            if (path_len >= sizeof(module_path)) continue;
            
            memcpy(module_path, quote_start + 1, path_len);
            module_path[path_len] = '\0';
            
            /* Check if it's a directory or a single file */
            /* Construct the full path to check */
            char full_module_path[1024];
            const char *last_slash = strrchr(source_filename, '/');
            if (last_slash) {
                size_t dir_len = last_slash - source_filename + 1;
                if (dir_len + strlen(module_path) + 1 > sizeof(full_module_path)) continue;
                memcpy(full_module_path, source_filename, dir_len);
                strcpy(full_module_path + dir_len, module_path);
            } else {
                if (strlen(module_path) + 1 > sizeof(full_module_path)) continue;
                strcpy(full_module_path, module_path);
            }
            
            struct stat st;
            if (stat(full_module_path, &st) == 0 && S_ISDIR(st.st_mode)) {
                /* It's a directory - scan for .cz.h files */
                DIR *dir = opendir(full_module_path);
                if (dir) {
                    struct dirent *entry;
                    while ((entry = readdir(dir)) != NULL) {
                        /* Check if file ends with .cz.h */
                        size_t name_len = strlen(entry->d_name);
                        if (name_len > 5 && strcmp(entry->d_name + name_len - 5, ".cz.h") == 0) {
                            /* Validate path length before constructing */
                            if (strlen(module_path) + 1 + name_len + 1 > MAX_PATH_LEN) {
                                continue; /* Path too long, skip this file */
                            }
                            /* Parse this header file */
                            char header_path[MAX_PATH_LEN];
                            snprintf(header_path, sizeof(header_path), "%s/%s", module_path, entry->d_name);
                            parse_header_for_typedefs(source_filename, header_path);
                        }
                    }
                    closedir(dir);
                }
            } else {
                /* Validate path length before constructing */
                if (strlen(module_path) + 5 + 1 > MAX_PATH_LEN) {
                    continue; /* Path too long, skip */
                }
                /* Try single file: module_path.cz.h */
                char header_path[MAX_PATH_LEN];
                snprintf(header_path, sizeof(header_path), "%s.cz.h", module_path);
                parse_header_for_typedefs(source_filename, header_path);
            }
        }
    }
}

/* Scan for existing typedef struct patterns in the AST and track them
 * This is needed for when using structs defined in other imported files
 * Pattern: typedef struct Name_s { ... } Name_t;
 * We want to track: Name -> Name_t
 */
static void scan_existing_typedefs(ASTNode_t *ast) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    /* Look for pattern: typedef struct Name_s { ... } Name_t; */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            continue;
        }
        
        Token *t = &ast->children[i]->token;
        
        /* Look for "typedef struct" */
        if (t->type == TOKEN_IDENTIFIER && t->text && strcmp(t->text, "typedef struct") == 0) {
            /* Find the struct tag name (should end with _s) */
            size_t tag_idx = i + 1;
            while (tag_idx < ast->child_count && ast->children[tag_idx]->type == AST_TOKEN &&
                   ast->children[tag_idx]->token.type == TOKEN_WHITESPACE) {
                tag_idx++;
            }
            
            if (tag_idx >= ast->child_count || ast->children[tag_idx]->type != AST_TOKEN ||
                ast->children[tag_idx]->token.type != TOKEN_IDENTIFIER) {
                continue;
            }
            
            char *tag_name = ast->children[tag_idx]->token.text;
            if (!tag_name) {
                continue;
            }
            
            /* Check if it ends with _s */
            size_t tag_len = strlen(tag_name);
            if (tag_len <= 2 || strcmp(tag_name + tag_len - 2, "_s") != 0) {
                continue;
            }
            
            /* Extract base name by removing _s suffix */
            char *base_name = strndup(tag_name, tag_len - 2);
            if (!base_name) {
                continue;
            }
            
            /* Find closing brace to locate typedef name */
            size_t brace_idx = tag_idx + 1;
            while (brace_idx < ast->child_count && ast->children[brace_idx]->type == AST_TOKEN) {
                Token *bt = &ast->children[brace_idx]->token;
                if (bt->type == TOKEN_PUNCTUATION && bt->text && strcmp(bt->text, "{") == 0) {
                    break;
                }
                brace_idx++;
            }
            
            if (brace_idx >= ast->child_count) {
                free(base_name);
                continue;
            }
            
            /* Find matching closing brace */
            int brace_depth = 0;
            size_t closing_brace_idx = 0;
            for (size_t j = brace_idx; j < ast->child_count; j++) {
                if (ast->children[j]->type == AST_TOKEN) {
                    Token *tj = &ast->children[j]->token;
                    if (tj->type == TOKEN_PUNCTUATION && tj->text) {
                        if (strcmp(tj->text, "{") == 0) {
                            brace_depth++;
                        } else if (strcmp(tj->text, "}") == 0) {
                            brace_depth--;
                            if (brace_depth == 0) {
                                closing_brace_idx = j;
                                break;
                            }
                        }
                    }
                }
            }
            
            if (closing_brace_idx == 0) {
                free(base_name);
                continue;
            }
            
            /* Find typedef name after closing brace */
            size_t typedef_idx = closing_brace_idx + 1;
            while (typedef_idx < ast->child_count && ast->children[typedef_idx]->type == AST_TOKEN &&
                   ast->children[typedef_idx]->token.type == TOKEN_WHITESPACE) {
                typedef_idx++;
            }
            
            if (typedef_idx < ast->child_count && ast->children[typedef_idx]->type == AST_TOKEN &&
                ast->children[typedef_idx]->token.type == TOKEN_IDENTIFIER) {
                char *typedef_name = ast->children[typedef_idx]->token.text;
                if (typedef_name) {
                    /* Check if typedef ends with _t */
                    size_t typedef_len = strlen(typedef_name);
                    if (typedef_len > 2 && strcmp(typedef_name + typedef_len - 2, "_t") == 0) {
                        /* Track the mapping: base_name -> typedef_name */
                        track_struct_name(base_name, typedef_name);
                    }
                }
            }
            
            free(base_name);
        }
    }
}

/* Replace all uses of tracked struct names with their _t variants
 * For example: Vec2 -> Vec2_t
 * This ensures the generated C code uses the typedef names consistently
 * Special case: "struct Name" stays as "struct Name_s" (uses struct tag)
 */
void transpiler_replace_struct_names(ASTNode_t *ast, const char *filename) {
    if (!ast || ast->type != AST_TRANSLATION_UNIT) {
        return;
    }
    
    /* First, scan for #import directives and parse imported .cz.h files */
    if (filename) {
        scan_imports_for_typedefs(ast, filename);
    }
    
    /* Then, scan for existing typedef patterns in the current AST */
    scan_existing_typedefs(ast);

    /* Walk through all tokens and replace struct names */
    for (size_t i = 0; i < ast->child_count; i++) {
        if (ast->children[i]->type != AST_TOKEN) {
            continue;
        }
        
        Token *t = &ast->children[i]->token;
        
        /* Check if this is an identifier we need to replace */
        if (t->type == TOKEN_IDENTIFIER && t->text) {
            const char *typedef_name = get_typedef_name(t->text);
            
            if (typedef_name) {
                /* Check if preceded by "struct" keyword - if so, skip replacement */
                /* because "struct Name" should stay as "struct Name_s" which was already done */
                int preceded_by_struct = 0;
                if (i > 0) {
                    /* Look backwards for non-whitespace token */
                    for (int j = (int)i - 1; j >= 0; j--) {
                        if (ast->children[j]->type == AST_TOKEN) {
                            Token *prev = &ast->children[j]->token;
                            if (prev->type == TOKEN_WHITESPACE || prev->type == TOKEN_COMMENT) {
                                continue;
                            }
                            /* Found a non-whitespace token */
                            /* Note: "typedef struct" is a single token created during transformation */
                            if (prev->type == TOKEN_IDENTIFIER && prev->text && 
                                (strcmp(prev->text, "struct") == 0 || strcmp(prev->text, "typedef struct") == 0)) {
                                preceded_by_struct = 1;
                            }
                            break;
                        }
                    }
                }
                
                if (!preceded_by_struct) {
                    /* Replace Name with Name_t */
                    char *new_text = strdup(typedef_name);
                    if (new_text) {
                        free(t->text);
                        t->text = new_text;
                        t->length = strlen(new_text);
                    }
                }
            }
        }
    }
}
