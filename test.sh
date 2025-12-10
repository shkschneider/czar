#!/usr/bin/env bash -eu

abrt() { exit 1 ; }
trap abrt ABRT

echo "Running tests from test/ directory..."
for file in test/*_test.c ; do
    if [ -f "$file" ]; then
        basename="${file##*/}"
        f="test/${basename%.*}"
        echo "  $basename..."
        cc -std=c2x -I . \
            -W -Werror -Wall -Wstrict-prototypes \
            -g -funroll-loops -O3 \
            -lc -lm \
        "$file" -static -o "$f" && "./$f" && {
            rm -f "./$f"
        } || {
            rm -f "./$f"
            exit 1
        }
    fi
done

echo "All tests passed!"

# EOF
