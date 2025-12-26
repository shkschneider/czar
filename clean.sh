#!/usr/bin/env bash

rm -rf ./build

find ./bench/c  -type f                -name '*.o' -o -name '*.s' -exec rm -vf -- {} +
find ./bench/cz -type f -name '*.c' -o -name '*.o' -o -name '*.s' -exec rm -vf -- {} +
find ./bench    -type f -executable                               -exec rm -vf -- {} +

find ./dist  -type f -executable -exec rm -vf -- {} +
find ./dist  -type f -name '*.a' -or -name '*.c' -or -name '*.h' -or -name '*.s' -exec rm -vf -- {} +
find ./tests -type f -executable -exec rm -vf -- {} +
find ./tests -type f -name '*.c' -or -name '*.s' -exec rm -vf -- {} +

find . -type f -name '*.out' -exec rm -vf -- {} +
rm -rf ./dist
