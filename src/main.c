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
extern const char luaJIT_BC_codegen_init[];
extern const char luaJIT_BC_codegen_types[];
extern const char luaJIT_BC_codegen_memory[];
extern const char luaJIT_BC_codegen_functions[];
extern const char luaJIT_BC_codegen_statements[];
extern const char luaJIT_BC_codegen_expressions[];
extern const char luaJIT_BC_generate[];
extern const char luaJIT_BC_assemble[];
extern const char luaJIT_BC_build[];
extern const char luaJIT_BC_run[];

// Declare external size symbols (defined in bytecode_sizes.c)
extern const size_t luaJIT_BC_main_size;
extern const size_t luaJIT_BC_lexer_init_size;
extern const size_t luaJIT_BC_parser_init_size;
extern const size_t luaJIT_BC_codegen_init_size;
extern const size_t luaJIT_BC_codegen_types_size;
extern const size_t luaJIT_BC_codegen_memory_size;
extern const size_t luaJIT_BC_codegen_functions_size;
extern const size_t luaJIT_BC_codegen_statements_size;
extern const size_t luaJIT_BC_codegen_expressions_size;
extern const size_t luaJIT_BC_generate_size;
extern const size_t luaJIT_BC_assemble_size;
extern const size_t luaJIT_BC_build_size;
extern const size_t luaJIT_BC_run_size;

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
        load_module(L, "codegen", luaJIT_BC_codegen_init, luaJIT_BC_codegen_init_size) != 0 ||
        load_module(L, "codegen.types", luaJIT_BC_codegen_types, luaJIT_BC_codegen_types_size) != 0 ||
        load_module(L, "codegen.memory", luaJIT_BC_codegen_memory, luaJIT_BC_codegen_memory_size) != 0 ||
        load_module(L, "codegen.functions", luaJIT_BC_codegen_functions, luaJIT_BC_codegen_functions_size) != 0 ||
        load_module(L, "codegen.statements", luaJIT_BC_codegen_statements, luaJIT_BC_codegen_statements_size) != 0 ||
        load_module(L, "codegen.expressions", luaJIT_BC_codegen_expressions, luaJIT_BC_codegen_expressions_size) != 0 ||
        load_module(L, "generate", luaJIT_BC_generate, luaJIT_BC_generate_size) != 0 ||
        load_module(L, "assemble", luaJIT_BC_assemble, luaJIT_BC_assemble_size) != 0 ||
        load_module(L, "build", luaJIT_BC_build, luaJIT_BC_build_size) != 0 ||
        load_module(L, "run", luaJIT_BC_run, luaJIT_BC_run_size) != 0) {
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
