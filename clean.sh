#!/usr/bin/env bash

rm -vf ./*.o ./main.h ./*.a ./cz ./a.out

find ./tests -type f -name '*.c' -print | xargs rm -vf
find ./tests -type f -executable -print | xargs rm -vf
