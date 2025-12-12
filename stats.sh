#!/usr/bin/env bash

r=0
for f in *.lua *.sh ; do
    l=$(wc -l $f | cut -d' ' -f1)
    (( r += l ))
    n=${f%.*}
    n=${n^}
    echo "$n: $l"
    while read m ; do
        echo "- $m"
    done < <(grep "function $n" $f | cut -d' ' -f2- | cut -d'(' -f1 | tr ':' '.' | cut -d'.' -f2 | sort -u)
done
echo "$r"

# EOF
