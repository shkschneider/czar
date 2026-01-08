#!/bin/bash
# CZar multi-file build script
set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

DIR="$1"
CZ_BIN="${CZ_BIN:-./build/cz}"

echo "Building CZar project in $DIR..."

# Find all .cz files
CZ_FILES=$(find "$DIR" -name "*.cz")

# Transpile each .cz file to .c and generate header
for czfile in $CZ_FILES; do
    echo "Transpiling $czfile..."
    cfile="${czfile}.c"
    hfile="${czfile}.h"
    
    "$CZ_BIN" "$czfile" "$cfile"
    
    # Generate simple header
    echo "/* Generated header for $czfile */" > "$hfile"
    echo "#pragma once" >> "$hfile"
    grep -E '^[a-zA-Z_][a-zA-Z0-9_*]+ +[a-zA-Z_][a-zA-Z0-9_]+\(' "$czfile" | sed 's/{.*/;/' >> "$hfile" || true
done

echo "Build complete!"
