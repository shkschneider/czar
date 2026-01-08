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

# Step 1: Transpile to .c (also generates .h automatically)
echo "=== Transpiling (generates .c and .h) ==="
for czfile in $CZ_FILES; do
    echo "  $czfile -> ${czfile}.c + ${czfile}.h"
    "$CZ_BIN" "$czfile" "${czfile}.c"
done

# Step 2: Transform #import directives to #include
echo "=== Transforming #import directives ==="
for czfile in $CZ_FILES; do
    cfile="${czfile}.c"
    
    # Check if file has #import directives (comments that start with /* #import)
    if grep -q '/\* #import' "$cfile"; then
        echo "  Processing imports in: $cfile"
        tmpfile="${cfile}.tmp"
        
        # Process each #import comment
        awk -v dir="$DIR" '
            /\/\* #import "([^"]+)" / {
                # Extract the import path
                match($0, /"([^"]+)"/, arr)
                import_path = arr[1]
                
                # Find all .cz.h files in that directory
                cmd = "find " dir "/" import_path " -maxdepth 1 -name \"*.cz.h\" 2>/dev/null | sort"
                includes = ""
                while ((cmd | getline header) > 0) {
                    # Extract just the filename
                    n = split(header, parts, "/")
                    filename = parts[n]
                    includes = includes "#include \"" import_path "/" filename "\"\n"
                }
                close(cmd)
                
                if (includes != "") {
                    printf "%s", includes
                } else {
                    print "/* #import \"" import_path "\" - no headers found */"
                }
                next
            }
            { print }
        ' "$cfile" > "$tmpfile"
        mv "$tmpfile" "$cfile"
    fi
done

# Step 3: Add includes for same-directory headers
echo "=== Adding same-directory header includes ==="
for czfile in $CZ_FILES; do
    cfile="${czfile}.c"
    dir=$(dirname "$czfile")
    base=$(basename "$czfile" .cz)
    
    # Find all .h files in the same directory (excluding own header)
    headers=$(find "$dir" -maxdepth 1 -name "*.cz.h" ! -name "${base}.cz.h" 2>/dev/null || true)
    
    if [ -n "$headers" ]; then
        echo "  Adding includes to: $cfile"
        tmpfile="${cfile}.tmp"
        
        # Insert includes after the self-include
        awk -v headers="$headers" '
            /#include.*\.cz\.h/ && !done {
                print
                # Add other headers from same directory
                n = split(headers, h, " ")
                for (i=1; i<=n; i++) {
                    if (h[i] != "") {
                        m = split(h[i], parts, "/")
                        print "#include \"" parts[m] "\""
                    }
                }
                done = 1
                next
            }
            { print }
        ' "$cfile" > "$tmpfile"
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
