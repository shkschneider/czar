#!/usr/bin/env bash

stats() {
    r=0
    while read f ; do
        local l=$(wc -l $f | cut -d' ' -f1)
        (( r += l ))
        echo "$f: $l"
        local n=${f%.*}
        n=${n##*/}
        n=${n^}
        while read m ; do
            echo "- $m"
        done < <(grep "function $n:" $f | cut -d' ' -f2- | cut -d'(' -f1 | tr ':' '.' | cut -d'.' -f2 | sort -u)
    done < <(find src -type f)
    echo "*: $r"
}

./clean.sh >/dev/null
stats | awk '{print $2" "$1}' | sort -n | awk '{print $2" "$1}'

# EOF
