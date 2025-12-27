#!/usr/bin/env bash

# Test Coverage Analysis Script
# Analyzes test coverage and provides statistics

set -e
./clean.sh >/dev/null

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
BLUE="\e[34m"
WHITE="\e[0m"

echo -e "${BLUE}=== Czar Test Coverage Report ===${WHITE}\n"

# Count test files
OK_TESTS=$(find tests/ok -name "*.cz" -type f | wc -l)
KO_TESTS=$(find tests/ko -name "*.cz" -type f | wc -l)
FAIL_TESTS=$(find tests/fail -name "*.cz" -type f | wc -l)
TOTAL_TESTS=$((OK_TESTS + KO_TESTS + FAIL_TESTS))

echo -e "${GREEN}Test Files:${WHITE}"
echo "  Positive tests (ok/):    $OK_TESTS"
echo "  Negative tests (ko/):    $KO_TESTS"
echo "  Work-in-progress (fail/): $FAIL_TESTS"
echo "  Total:                    $TOTAL_TESTS"
echo

# Analyze test categories
echo -e "${GREEN}Test Categories (ok/):${WHITE}"

count_tests() {
    local pattern=$1
    local count=$(find tests/ok -name "${pattern}*.cz" -type f | wc -l)
    echo "$count"
}

# Categories based on common prefixes
echo "  Arrays:            $(count_tests 'array')"
echo "  Strings:           $(count_tests 'string')"
echo "  Pointers:          $(count_tests 'pointer')"
echo "  Functions:         $(count_tests 'function')"
echo "  Structs:           $(count_tests 'struct')"
echo "  Methods:           $(count_tests 'method')"
echo "  Interfaces:        $(count_tests 'iface')"
echo "  Enums:             $(count_tests 'enum')"
echo "  Generics:          $(count_tests 'generic')"
echo "  Memory (new/free): $(count_tests 'new')"
echo "  Arena allocator:   $(count_tests 'arena')"
echo "  Defer:             $(count_tests 'defer')"
echo "  Loops (for/while): $(count_tests 'for')$(count_tests 'while')$(count_tests 'loop')"
echo "  Conditionals:      $(count_tests 'if')"
echo "  Macros:            $(count_tests 'macro')"
echo "  Modules:           $(count_tests 'module')"
echo "  Imports:           $(count_tests 'import')"
echo "  Varargs:           $(count_tests 'varargs')"
echo "  Anonymous:         $(count_tests 'anonymous')"
echo "  Maps:              $(count_tests 'map')"
echo "  Pairs:             $(count_tests 'pair')"
echo

# Analyze error test categories
echo -e "${GREEN}Error Test Categories (ko/):${WHITE}"

count_ko_tests() {
    local pattern=$1
    local count=$(find tests/ko -name "${pattern}*.cz" -type f | wc -l)
    echo "$count"
}

echo "  Type mismatches:   $(count_ko_tests 'type_mismatch')"
echo "  Undefined:         $(count_ko_tests 'undefined')"
echo "  Duplicates:        $(count_ko_tests 'duplicate')"
echo "  Array bounds:      $(count_ko_tests 'array_bounds')"
echo "  Null errors:       $(count_ko_tests 'null')"
echo "  Access violations: $(count_ko_tests 'prv')"
echo "  Invalid casts:     $(count_ko_tests 'cast')"
echo "  Missing elements:  $(count_ko_tests 'missing')"
echo

# Language features from FEATURES.md
echo -e "${GREEN}Feature Coverage:${WHITE}"

check_feature() {
    local feature=$1
    local pattern=$2
    local count=$(find tests/ok tests/ko -name "*${pattern}*" -type f | wc -l)
    if [ $count -gt 0 ]; then
        echo -e "  ${GREEN}✓${WHITE} $feature ($count tests)"
    else
        echo -e "  ${RED}✗${WHITE} $feature (0 tests)"
    fi
}

check_feature "Arithmetic operators" "arithmetic"
check_feature "Logical operators" "logical"
check_feature "Bitwise operators" "bitwise"
check_feature "Comparison operators" "comparison"
check_feature "Type casting" "cast"
check_feature "Null handling" "null"
check_feature "Mutability" "mut"
check_feature "Visibility (pub/prv)" "pub\|prv"
check_feature "Structs" "struct"
check_feature "Functions" "function"
check_feature "Methods" "method"
check_feature "Interfaces" "iface"
check_feature "Enums" "enum"
check_feature "Generics" "generic"
check_feature "Arrays" "array"
check_feature "Slices" "slice"
check_feature "Strings" "string"
check_feature "Maps" "map"
check_feature "Pairs" "pair"
check_feature "Pointers" "pointer"
check_feature "Memory allocation" "new\|free\|arena"
check_feature "Defer" "defer"
check_feature "Loops" "while\|for\|loop\|repeat"
check_feature "Conditionals" "if"
check_feature "Break/Continue" "break\|continue"
check_feature "Modules" "module"
check_feature "Imports" "import"
check_feature "Macros" "macro"
check_feature "Varargs" "varargs"
check_feature "Anonymous types" "anonymous"
check_feature "Named parameters" "named"
check_feature "Default parameters" "default"
check_feature "Operator overloading" "overload"
echo

# Test file size analysis
echo -e "${GREEN}Test Complexity:${WHITE}"
SMALL=$(find tests/ok tests/ko -name "*.cz" -type f -exec wc -l {} \; | awk '$1 < 30 {count++} END {print count+0}')
MEDIUM=$(find tests/ok tests/ko -name "*.cz" -type f -exec wc -l {} \; | awk '$1 >= 30 && $1 < 100 {count++} END {print count+0}')
LARGE=$(find tests/ok tests/ko -name "*.cz" -type f -exec wc -l {} \; | awk '$1 >= 100 {count++} END {print count+0}')
echo "  Small (<30 lines):   $SMALL"
echo "  Medium (30-100):     $MEDIUM"
echo "  Large (>100):        $LARGE"
echo

# Integration tests
echo -e "${GREEN}Integration Tests:${WHITE}"
APP_TESTS=$(find tests/ok/app tests/ko/app -name "*.cz" -type f 2>/dev/null | wc -l)
echo "  Multi-file apps:     $APP_TESTS"
echo

# Check for TODOs and FIXMEs in tests
echo -e "${GREEN}Test Quality Markers:${WHITE}"
TODO_COUNT=$(grep -r "#TODO\|// TODO" tests/*.cz tests/*/*.cz 2>/dev/null | wc -l)
FIXME_COUNT=$(grep -r "#FIXME\|// FIXME" tests/*.cz tests/*/*.cz 2>/dev/null | wc -l)
echo "  TODOs in tests:      $TODO_COUNT"
echo "  FIXMEs in tests:     $FIXME_COUNT"
echo

# Summary
echo -e "${BLUE}=== Summary ===${WHITE}"
echo "Total test coverage: $TOTAL_TESTS tests"
echo "Positive tests: ${OK_TESTS} ($(( OK_TESTS * 100 / TOTAL_TESTS ))%)"
echo "Negative tests: ${KO_TESTS} ($(( KO_TESTS * 100 / TOTAL_TESTS ))%)"
if [ $FAIL_TESTS -gt 0 ]; then
    echo -e "${YELLOW}Work-in-progress: ${FAIL_TESTS} tests need attention${WHITE}"
fi

# Recommendations
echo
echo -e "${BLUE}=== Recommendations ===${WHITE}"

# Check for gaps
HAS_GENERICS=$(find tests/ok tests/ko -name "*generic*" -type f | wc -l)
if [ $HAS_GENERICS -lt 5 ]; then
    echo -e "${YELLOW}⚠${WHITE} Add more generics tests (current: $HAS_GENERICS)"
fi

HAS_INTERFACE=$(find tests/ok tests/ko -name "*iface*" -type f | wc -l)
if [ $HAS_INTERFACE -lt 10 ]; then
    echo -e "${YELLOW}⚠${WHITE} Add more interface tests (current: $HAS_INTERFACE)"
fi

HAS_ENUM=$(find tests/ok tests/ko -name "*enum*" -type f | wc -l)
if [ $HAS_ENUM -lt 10 ]; then
    echo -e "${YELLOW}⚠${WHITE} Add more enum tests (current: $HAS_ENUM)"
fi

HAS_PERF=$(find tests -name "*perf*" -o -name "*bench*" -type f | wc -l)
if [ $HAS_PERF -eq 0 ]; then
    echo -e "${YELLOW}⚠${WHITE} Consider adding performance/benchmark tests"
fi

HAS_INTEGRATION=$(find tests -type d -name "app" | wc -l)
if [ $HAS_INTEGRATION -eq 0 ]; then
    echo -e "${YELLOW}⚠${WHITE} Consider adding more integration tests"
fi

echo -e "\n${GREEN}✓ Test coverage analysis complete${WHITE}"

# EOF
