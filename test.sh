#!/usr/bin/env bash -eu

abrt() { exit 1 ; }
trap abrt ABRT

for file in cz_*.c ; do
    f="${file%.*}"
    echo "$file..."
    cc -std=c2x -I . \
        -W -Werror -Wall -Wstrict-prototypes \
        -g -funroll-loops -O3 \
        -lc -lm \
    $file -static -o $f && ./$f && {
        rm -f "./$f"
    } || {
        rm -f "./$f"
        exit 1
    }
done

# EOF
