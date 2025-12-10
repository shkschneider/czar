#!/usr/bin/env lua

-- Test suite for the Czar lexer

local Lexer = require("lexer")

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected '%s', got '%s'", msg or "Assertion failed", expected, actual))
    end
end

local function test_basic_tokens()
    print("Testing basic tokens...")
    
    local source = "struct fn return"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(#tokens, 4, "Token count") -- 3 tokens + EOF
    assert_eq(tokens[1].type, "STRUCT", "First token")
    assert_eq(tokens[2].type, "FN", "Second token")
    assert_eq(tokens[3].type, "RETURN", "Third token")
    assert_eq(tokens[4].type, "EOF", "EOF token")
    
    print("✓ Basic tokens test passed")
end

local function test_operators()
    print("Testing operators...")
    
    local source = "+ - * / -> == != <= >= && ||"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "PLUS", "Plus operator")
    assert_eq(tokens[2].type, "MINUS", "Minus operator")
    assert_eq(tokens[3].type, "STAR", "Star operator")
    assert_eq(tokens[4].type, "SLASH", "Slash operator")
    assert_eq(tokens[5].type, "ARROW", "Arrow operator")
    assert_eq(tokens[6].type, "EQEQ", "Equality operator")
    assert_eq(tokens[7].type, "NE", "Not equal operator")
    assert_eq(tokens[8].type, "LE", "Less or equal operator")
    assert_eq(tokens[9].type, "GE", "Greater or equal operator")
    assert_eq(tokens[10].type, "AND", "AND operator")
    assert_eq(tokens[11].type, "OR", "OR operator")
    
    print("✓ Operators test passed")
end

local function test_identifiers_and_numbers()
    print("Testing identifiers and numbers...")
    
    local source = "myVar x123 456"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "IDENTIFIER", "First identifier")
    assert_eq(tokens[1].value, "myVar", "First identifier value")
    assert_eq(tokens[2].type, "IDENTIFIER", "Second identifier")
    assert_eq(tokens[2].value, "x123", "Second identifier value")
    assert_eq(tokens[3].type, "NUMBER", "Number token")
    assert_eq(tokens[3].value, "456", "Number value")
    
    print("✓ Identifiers and numbers test passed")
end

local function test_types()
    print("Testing type keywords...")
    
    local source = "i32 bool void"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "I32", "i32 type")
    assert_eq(tokens[2].type, "BOOL", "bool type")
    assert_eq(tokens[3].type, "VOID", "void type")
    
    print("✓ Type keywords test passed")
end

local function test_punctuation()
    print("Testing punctuation...")
    
    local source = "(){};:,"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "LPAREN", "Left paren")
    assert_eq(tokens[2].type, "RPAREN", "Right paren")
    assert_eq(tokens[3].type, "LBRACE", "Left brace")
    assert_eq(tokens[4].type, "RBRACE", "Right brace")
    assert_eq(tokens[5].type, "SEMICOLON", "Semicolon")
    assert_eq(tokens[6].type, "COLON", "Colon")
    assert_eq(tokens[7].type, "COMMA", "Comma")
    
    print("✓ Punctuation test passed")
end

local function test_line_comment()
    print("Testing line comments...")
    
    local source = "fn // this is a comment\nmain"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "FN", "First token before comment")
    assert_eq(tokens[2].type, "IDENTIFIER", "Token after comment")
    assert_eq(tokens[2].value, "main", "Identifier value after comment")
    
    print("✓ Line comment test passed")
end

local function test_block_comment()
    print("Testing block comments...")
    
    local source = "fn /* this is a\nmultiline comment */ main"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].type, "FN", "First token before comment")
    assert_eq(tokens[2].type, "IDENTIFIER", "Token after comment")
    assert_eq(tokens[2].value, "main", "Identifier value after comment")
    
    print("✓ Block comment test passed")
end

local function test_position_tracking()
    print("Testing position tracking...")
    
    local source = "fn\nmain"
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    assert_eq(tokens[1].line, 1, "First token line")
    assert_eq(tokens[1].column, 1, "First token column")
    assert_eq(tokens[2].line, 2, "Second token line")
    assert_eq(tokens[2].column, 1, "Second token column")
    
    print("✓ Position tracking test passed")
end

local function test_example_cz()
    print("Testing example.cz file...")
    
    local file = io.open("example.cz", "r")
    if not file then
        print("⚠ Skipping example.cz test (file not found)")
        return
    end
    
    local source = file:read("*all")
    file:close()
    
    local lexer = Lexer.new(source)
    local tokens = lexer:tokenize()
    
    -- Basic sanity checks
    assert_eq(tokens[#tokens].type, "EOF", "EOF token at end")
    assert(#tokens > 10, "Expected more than 10 tokens")
    
    -- Check that we have the expected keywords
    local has_struct = false
    local has_fn = false
    local has_return = false
    
    for _, token in ipairs(tokens) do
        if token.type == "STRUCT" then has_struct = true end
        if token.type == "FN" then has_fn = true end
        if token.type == "RETURN" then has_return = true end
    end
    
    assert_eq(has_struct, true, "Has struct keyword")
    assert_eq(has_fn, true, "Has fn keyword")
    assert_eq(has_return, true, "Has return keyword")
    
    print("✓ example.cz test passed")
end

-- Run all tests
local function run_tests()
    print("\n=== Running Czar Lexer Tests ===\n")
    
    local tests = {
        test_basic_tokens,
        test_operators,
        test_identifiers_and_numbers,
        test_types,
        test_punctuation,
        test_line_comment,
        test_block_comment,
        test_position_tracking,
        test_example_cz,
    }
    
    local passed = 0
    local failed = 0
    
    for _, test in ipairs(tests) do
        local success, err = pcall(test)
        if success then
            passed = passed + 1
        else
            failed = failed + 1
            print("✗ Test failed: " .. err)
        end
    end
    
    print("\n=== Test Results ===")
    print(string.format("Passed: %d", passed))
    print(string.format("Failed: %d", failed))
    
    if failed > 0 then
        os.exit(1)
    end
end

run_tests()
