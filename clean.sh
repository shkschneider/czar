#!/usr/bin/env bash

rm -rf ./build

find ./dist -type f \( \
    -executable -o -name '*.h' -o -name '*.a' \
\) -exec rm -vf -- {} +

find ./tests -type f \( \
    -executable -o -name '*.c' -o -name '*.s' \
\) -exec rm -vf -- {} +

rm -vf ./a.out ./cz
