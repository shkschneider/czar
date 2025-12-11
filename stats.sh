#!/usr/bin/env sh

r=0
for f in *.lua ; do
    l=$(wc -l $f | cut -d' ' -f1)
    (( r += l ))
    n=${f/.lua/}
    n=${n^}
    echo "$n: $l"
    while read m ; do
        echo "- $m"
    done < <(grep "function $n" $f | cut -d' ' -f2- | cut -d'(' -f1 | tr ':' '.' | cut -d'.' -f2 | sort -u)
done
echo "$r"

# EOF
