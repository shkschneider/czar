#!/usr/bin/env bash

r=0
while read f ; do
    l=$(wc -l $f | cut -d' ' -f1)
    (( r += l ))
    echo "$f: $l"
    n=${f%.*}
    n=${n##*/}
    n=${n^}
    while read m ; do
        echo "- $m"
    done < <(grep "function $n:" $f | cut -d' ' -f2- | cut -d'(' -f1 | tr ':' '.' | cut -d'.' -f2 | sort -u)
done < <(find src -type f)
echo "$r"
#./stats.sh | rev | cut -d' ' -f1 | rev | sort -n | xargs

# EOF
