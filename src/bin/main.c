#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <luajit.h>
#include <lualib.h>
#include <lauxlib.h>
#include "main.h"

// Declare external bytecode symbols
extern const char luaJIT_BC_main[];
extern const char luaJIT_BC_lexer_init[];
extern const char luaJIT_BC_parser_init[];
extern const char luaJIT_BC_typechecker_init[];
extern const char luaJIT_BC_typechecker_resolver[];
extern const char luaJIT_BC_typechecker_inference_init[];
extern const char luaJIT_BC_typechecker_inference_types[];
extern const char luaJIT_BC_typechecker_inference_literals[];
extern const char luaJIT_BC_typechecker_inference_expressions[];
extern const char luaJIT_BC_typechecker_inference_calls[];
extern const char luaJIT_BC_typechecker_inference_fields[];
extern const char luaJIT_BC_typechecker_inference_collections[];
extern const char luaJIT_BC_typechecker_mutability[];
extern const char luaJIT_BC_lowering_init[];
extern const char luaJIT_BC_analysis_init[];
extern const char luaJIT_BC_codegen_init[];
extern const char luaJIT_BC_codegen_types[];
extern const char luaJIT_BC_codegen_memory[];
extern const char luaJIT_BC_codegen_functions[];
extern const char luaJIT_BC_codegen_statements[];
extern const char luaJIT_BC_codegen_expressions_init[];
extern const char luaJIT_BC_codegen_expressions_literals[];
extern const char luaJIT_BC_codegen_expressions_operators[];
extern const char luaJIT_BC_codegen_expressions_calls[];
extern const char luaJIT_BC_codegen_expressions_collections[];
extern const char luaJIT_BC_errors[];
extern const char luaJIT_BC_warnings[];
extern const char luaJIT_BC_macros[];
extern const char luaJIT_BC_compile[];
extern const char luaJIT_BC_asm[];
extern const char luaJIT_BC_build[];
extern const char luaJIT_BC_run[];
extern const char luaJIT_BC_test[];
extern const char luaJIT_BC_format[];
extern const char luaJIT_BC_clean[];

// Declare external size symbols (defined in bytecode_sizes.c)
extern const size_t luaJIT_BC_main_size;
extern const size_t luaJIT_BC_lexer_init_size;
extern const size_t luaJIT_BC_parser_init_size;
extern const size_t luaJIT_BC_typechecker_init_size;
extern const size_t luaJIT_BC_typechecker_resolver_size;
extern const size_t luaJIT_BC_typechecker_inference_init_size;
extern const size_t luaJIT_BC_typechecker_inference_types_size;
extern const size_t luaJIT_BC_typechecker_inference_literals_size;
extern const size_t luaJIT_BC_typechecker_inference_expressions_size;
extern const size_t luaJIT_BC_typechecker_inference_calls_size;
extern const size_t luaJIT_BC_typechecker_inference_fields_size;
extern const size_t luaJIT_BC_typechecker_inference_collections_size;
extern const size_t luaJIT_BC_typechecker_mutability_size;
extern const size_t luaJIT_BC_lowering_init_size;
extern const size_t luaJIT_BC_analysis_init_size;
extern const size_t luaJIT_BC_codegen_init_size;
extern const size_t luaJIT_BC_codegen_types_size;
extern const size_t luaJIT_BC_codegen_memory_size;
extern const size_t luaJIT_BC_codegen_functions_size;
extern const size_t luaJIT_BC_codegen_statements_size;
extern const size_t luaJIT_BC_codegen_expressions_init_size;
extern const size_t luaJIT_BC_codegen_expressions_literals_size;
extern const size_t luaJIT_BC_codegen_expressions_operators_size;
extern const size_t luaJIT_BC_codegen_expressions_calls_size;
extern const size_t luaJIT_BC_codegen_expressions_collections_size;
extern const size_t luaJIT_BC_errors_size;
extern const size_t luaJIT_BC_warnings_size;
extern const size_t luaJIT_BC_macros_size;
extern const size_t luaJIT_BC_compile_size;
extern const size_t luaJIT_BC_asm_size;
extern const size_t luaJIT_BC_build_size;
extern const size_t luaJIT_BC_run_size;
extern const size_t luaJIT_BC_test_size;
extern const size_t luaJIT_BC_format_size;
extern const size_t luaJIT_BC_clean_size;

// Helper to load bytecode into package.preload
static int load_module(lua_State *L, const char *name, const char *bytecode, size_t size) {
    // Get package.preload table
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");

    // Load the bytecode
    if (luaL_loadbuffer(L, bytecode, size, name) != 0) {
        const char *err = lua_tostring(L, -1);
        if (err) {
            fprintf(stderr, "Failed to load module %s: %s\n", name, err);
        } else {
            fprintf(stderr, "Failed to load module %s\n", name);
        }
        return -1;
    }

    // Set package.preload[name] = loaded_chunk
    lua_setfield(L, -2, name);
    lua_pop(L, 2); // pop preload and package tables

    return 0;
}

int main(int argc, char **argv) {
    lua_State *L = luaL_newstate();
    if (!L) {
        fprintf(stderr, "Failed to create Lua state\n");
        return 1;
    }

    // Open standard libraries
    luaL_openlibs(L);

    // Set up arg table for Lua (arg[0] = program name, arg[1] = first argument, etc.)
    lua_newtable(L);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    // Load modules into package.preload
    if (load_module(L, "lexer", luaJIT_BC_lexer_init, luaJIT_BC_lexer_init_size) != 0 ||
        load_module(L, "parser", luaJIT_BC_parser_init, luaJIT_BC_parser_init_size) != 0 ||
        load_module(L, "typechecker", luaJIT_BC_typechecker_init, luaJIT_BC_typechecker_init_size) != 0 ||
        load_module(L, "typechecker.resolver", luaJIT_BC_typechecker_resolver, luaJIT_BC_typechecker_resolver_size) != 0 ||
        load_module(L, "typechecker.inference", luaJIT_BC_typechecker_inference_init, luaJIT_BC_typechecker_inference_init_size) != 0 ||
        load_module(L, "typechecker.inference.types", luaJIT_BC_typechecker_inference_types, luaJIT_BC_typechecker_inference_types_size) != 0 ||
        load_module(L, "typechecker.inference.literals", luaJIT_BC_typechecker_inference_literals, luaJIT_BC_typechecker_inference_literals_size) != 0 ||
        load_module(L, "typechecker.inference.expressions", luaJIT_BC_typechecker_inference_expressions, luaJIT_BC_typechecker_inference_expressions_size) != 0 ||
        load_module(L, "typechecker.inference.calls", luaJIT_BC_typechecker_inference_calls, luaJIT_BC_typechecker_inference_calls_size) != 0 ||
        load_module(L, "typechecker.inference.fields", luaJIT_BC_typechecker_inference_fields, luaJIT_BC_typechecker_inference_fields_size) != 0 ||
        load_module(L, "typechecker.inference.collections", luaJIT_BC_typechecker_inference_collections, luaJIT_BC_typechecker_inference_collections_size) != 0 ||
        load_module(L, "typechecker.mutability", luaJIT_BC_typechecker_mutability, luaJIT_BC_typechecker_mutability_size) != 0 ||
        load_module(L, "lowering", luaJIT_BC_lowering_init, luaJIT_BC_lowering_init_size) != 0 ||
        load_module(L, "analysis", luaJIT_BC_analysis_init, luaJIT_BC_analysis_init_size) != 0 ||
        load_module(L, "codegen", luaJIT_BC_codegen_init, luaJIT_BC_codegen_init_size) != 0 ||
        load_module(L, "codegen.types", luaJIT_BC_codegen_types, luaJIT_BC_codegen_types_size) != 0 ||
        load_module(L, "codegen.memory", luaJIT_BC_codegen_memory, luaJIT_BC_codegen_memory_size) != 0 ||
        load_module(L, "codegen.functions", luaJIT_BC_codegen_functions, luaJIT_BC_codegen_functions_size) != 0 ||
        load_module(L, "codegen.statements", luaJIT_BC_codegen_statements, luaJIT_BC_codegen_statements_size) != 0 ||
        load_module(L, "codegen.expressions", luaJIT_BC_codegen_expressions_init, luaJIT_BC_codegen_expressions_init_size) != 0 ||
        load_module(L, "codegen.expressions.literals", luaJIT_BC_codegen_expressions_literals, luaJIT_BC_codegen_expressions_literals_size) != 0 ||
        load_module(L, "codegen.expressions.operators", luaJIT_BC_codegen_expressions_operators, luaJIT_BC_codegen_expressions_operators_size) != 0 ||
        load_module(L, "codegen.expressions.calls", luaJIT_BC_codegen_expressions_calls, luaJIT_BC_codegen_expressions_calls_size) != 0 ||
        load_module(L, "codegen.expressions.collections", luaJIT_BC_codegen_expressions_collections, luaJIT_BC_codegen_expressions_collections_size) != 0 ||
        load_module(L, "errors", luaJIT_BC_errors, luaJIT_BC_errors_size) != 0 ||
        load_module(L, "warnings", luaJIT_BC_warnings, luaJIT_BC_warnings_size) != 0 ||
        load_module(L, "macros", luaJIT_BC_macros, luaJIT_BC_macros_size) != 0 ||
        load_module(L, "compile", luaJIT_BC_compile, luaJIT_BC_compile_size) != 0 ||
        load_module(L, "asm", luaJIT_BC_asm, luaJIT_BC_asm_size) != 0 ||
        load_module(L, "build", luaJIT_BC_build, luaJIT_BC_build_size) != 0 ||
        load_module(L, "run", luaJIT_BC_run, luaJIT_BC_run_size) != 0 ||
        load_module(L, "test", luaJIT_BC_test, luaJIT_BC_test_size) != 0 ||
        load_module(L, "format", luaJIT_BC_format, luaJIT_BC_format_size) != 0 ||
        load_module(L, "clean", luaJIT_BC_clean, luaJIT_BC_clean_size) != 0) {
        lua_close(L);
        return 1;
    }

    // Load and run the main script
    if (luaL_loadbuffer(L, luaJIT_BC_main, luaJIT_BC_main_size, "main") != 0) {
        const char *err = lua_tostring(L, -1);
        if (err) {
            fprintf(stderr, "Failed to load main script: %s\n", err);
        } else {
            fprintf(stderr, "Failed to load main script\n");
        }
        lua_close(L);
        return 1;
    }

    if (lua_pcall(L, 0, 0, 0) != 0) {
        const char *err = lua_tostring(L, -1);
        if (err) {
            fprintf(stderr, "Error: %s\n", err);
        } else {
            fprintf(stderr, "Error running script\n");
        }
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
