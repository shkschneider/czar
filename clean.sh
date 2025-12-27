#!/usr/bin/env bash

rm -rf ./build

while read f ; do
    rm -vf -- "./$f"
done < <(
    find bench/cz tests -type f \( -name '*.c' \) -print ;
    find * -type f \( -name '*.s' -o -name '*.o' \) -print ;
    find * -type f -executable ! -name '*.sh'
)

# EOF
