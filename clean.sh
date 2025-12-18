#!/usr/bin/env bash

rm -rf ./build

find ./dist ./tests -type f \( \
    -executable -o -name '*.h' -o -name '*.c' -o -name '*.o' -o -name '*.s' \
\) -exec rm -vf -- {} +

rm -vf ./a.out ./cz
