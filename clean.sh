#!/usr/bin/env bash

rm -rf ./build

find   ./bench/cz -type f -name '*.c'   -exec rm -vf -- {} +
find   ./bench    -type f -executable   -exec rm -vf -- {} +

find   ./tests    -type f -name '*.c'   -exec rm -vf -- {} +
find   ./tests    -type f -executable   -exec rm -vf -- {} +

find   .          -type f -name '*.o'   -exec rm -vf -- {} +
find   .          -type f -name '*.s'   -exec rm -vf -- {} +
find   .          -type f -name '*.out' -exec rm -vf -- {} +

rm -vf ./cz
