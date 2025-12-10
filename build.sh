#!/usr/bin/env bash -eu

set -x

cc -std=c2x -I . \
    -W -Werror -Wall -Wstrict-prototypes \
    -g -funroll-loops -O3 \
    -lc -lm \
    main.c \
    -static \
    -o cz

# EOF
