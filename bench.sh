#!/usr/bin/env bash

./build.sh || exit 1

ms() { echo $(( $(date +%s%N) / 1000 / 1000 )); }

OUT="cz"
CZ=()
C=()
for p in ./bench/cz/*.cz ; do
    d=${p%/*} ; d=${d%/*}
    f=${p##*/}
    cz="$d/cz/${f}"
    c="$d/c/${f/.cz/.c}"
    if [[ -f $cz ]] && [[ -f $c ]] ; then
        echo "- ${f/.cz/} ..."
        ./$OUT compile $cz -o ${cz/.cz/.out} >/dev/null || continue
        cc ${cz/.cz/.c} -o ${cz/.cz/.out} >/dev/null || continue
        start=$(ms)
        ./${cz/.cz/.out} >/dev/null
        CZ+=( $(( $(ms) - start )) )
        cc $c -o ${c/.c/.out} >/dev/null || continue
        start=$(ms)
        ./${c/.c/.out} >/dev/null
        C+=( $(( $(ms) - start )) )
    fi
done

CZ=($(for n in ${CZ[@]}; do printf "%.1f\n" $n; done | sort -n))
echo "CZar: ~ ${CZ[${#CZ[*]}/(${#CZ}-1)]} ms"
C=($(for n in ${C[@]}; do printf "%.1f\n" $n; done | sort -n))
echo "C:    ~ ${C[${#C[*]}/(${#C}-1)]} ms"

# EOF
