#!/usr/bin/env bash

# test "$# > 1" || {
#     echo "$0 <build|test>" >&2
#     exit 1
# }

set -eu

test() {
    abrt() { exit 1 ; }
    trap abrt ABRT
    for file in cz_*.c ; do
        f="${file%.*}"
        echo "$file..."
        cc="cc -std=c2x -I . \
            -W -Werror -Wall -Wstrict-prototypes \
            -g -funroll-loops -O3 \
            -lc -lm \
        $file -static -o $f"
        echo "+ $cc" | xargs
        $cc && ./$f && {
            rm -f "./$f"
        } || {
            rm -f "./$f"
            exit 1
        }
    done
}

build() {
    cc="cc -std=c2x -I . \
        -W -Werror -Wall -Wstrict-prototypes \
        -g -funroll-loops -O3 \
        -lc -lm \
        main.c -static -o cz"
    echo "+ $cc" | xargs
    $cc
}

run() {
    echo "+ ./cz"
    ./cz
}

for ARG in $@ ; do
    case "$ARG" in
        t|test) test ;;
        b|build) build ;;
        r|run) run ;;
        *) exit 1 ;;
    esac
done

# EOF
