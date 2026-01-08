#!/bin/bash
# CZar multi-file build script
set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <directory> [output_binary]"
    exit 1
fi

DIR="$1"
OUTPUT="${2:-program}"
CZ_BIN="${CZ_BIN:-./build/cz}"
CC="${CC:-cc}"
CFLAGS="-std=c11 -Wall -Wextra -O2"

echo "=== CZar Multi-File Build ==="
echo "Building project in: $DIR"

# Find all .cz files
CZ_FILES=$(find "$DIR" -name "*.cz" | sort)

if [ -z "$CZ_FILES" ]; then
    echo "Error: No .cz files found"
    exit 1
fi

# Step 1: Transpile to .c
echo "=== Transpiling ==="
for czfile in $CZ_FILES; do
    echo "  $czfile -> ${czfile}.c"
    "$CZ_BIN" "$czfile" "${czfile}.c"
done

# Step 2: Generate headers from .c files with proper types
echo "=== Generating headers ==="
for czfile in $CZ_FILES; do
    hfile="${czfile}.h"
    echo "  ${czfile}.c -> $hfile"
    {
        echo "/* Generated header */"
        echo "#pragma once"
        echo "#include <stdint.h>"
        echo "#include <stddef.h>"
        echo "#include <stdbool.h>"
        echo ""
        grep -E '^[a-zA-Z_][a-zA-Z0-9_]+ [a-zA-Z_][a-zA-Z0-9_]+\([^)]*\) \{$' "${czfile}.c" | sed 's/ {$/;/' || true
    } > "$hfile"
done

# Step 3: Add includes
echo "=== Adding header includes ==="
for czfile in $CZ_FILES; do
    cfile="${czfile}.c"
    dir=$(dirname "$czfile")
    base=$(basename "$czfile" .cz)
    
    headers=$(find "$dir" -maxdepth 1 -name "*.cz.h" ! -name "${base}.cz.h" 2>/dev/null || true)
    
    if [ -n "$headers" ]; then
        tmpfile="${cfile}.tmp"
        awk -v dir="$dir" '
            /^int main\(/ || /^[a-z]/ && NR > 300 && !done {
                for (h in ARGV) {
                    if (ARGV[h] ~ /\.h$/) {
                        n = split(ARGV[h], parts, "/")
                        print "#include \"" parts[n] "\""
                    }
                }
                print ""
                done = 1
                delete ARGV
            }
            { print }
        ' "$cfile" $headers > "$tmpfile"
        mv "$tmpfile" "$cfile"
    fi
done

# Step 4: Compile
echo "=== Compiling ==="
OBJ_FILES=""
for czfile in $CZ_FILES; do
    ofile="${czfile}.o"
    echo "  ${czfile}.c -> $ofile"
    $CC $CFLAGS -c "${czfile}.c" -o "$ofile" 2>&1 | grep -v "warning:" || true
    OBJ_FILES="$OBJ_FILES $ofile"
done

# Step 5: Link
OUTPUT_PATH="$DIR/$OUTPUT"
echo "=== Linking to $OUTPUT_PATH ==="
$CC $OBJ_FILES -o "$OUTPUT_PATH"

echo "=== Build Complete! ==="
