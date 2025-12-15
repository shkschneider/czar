#!/usr/bin/env bash

set +e
./build.sh || exit 1

ok=0
ko=0

# expected to exit 0
check_ok() {
    local f=$1
    local n=$f
    n=${n##*/}
    echo -n "[tests/ok] $n..."
    local o=${f/.cz/.out}
    ./cz build $f -o $o >/dev/null 2>/tmp/cz
    if [[ ! -x $o ]] ; then
        echo " ERROR (compilation failed):"
        cat /tmp/cz >&2
        (( ko += 1 ))
    else
        ./$o >/dev/null 2>/tmp/cz && {
            echo " SUCCESS"
            (( ok += 1 ))
        } || {
            e=$?
            echo " FAILURE: $e"
            (( ko += 1 ))
        }
        rm -f ./$o
    fi
    rm -f /tmp/cz
}

# expected to fail compilation (or exit non-zero)
check_ko() {
    local f=$1
    local n=$f
    n=${n##*/}
    echo -n "[test/ko] $n..."
    local o=${f/.cz/.out}
    ./cz build $f -o $o >/dev/null 2>/tmp/cz
    local e=$?
    if [[ $e -ne 0 ]] ; then
        echo " SUCCESS"
        (( ok += 1 ))
    else
        ./$o >/dev/null 2>/tmp/cz && {
            echo " FAILURE"
            (( ko += 1 ))
        } || {
            e=$?
            [[ $e -ne 134 ]] && echo " SUCCESS" # core dump
            (( ok += 1 ))
        }
        rm -f ./$o
    fi
    rm -f /tmp/cz
}

shopt -s nullglob
[[ $# -ge 1 ]] || set -- tests/ok/*.cz tests/ko/*.cz tests/*.cz

check() {
    for t in $@ ; do
        p=${t%/*}
        p=${p##*/}
        if [[ $p == "ko" ]] ; then
            check_ko "$t"
        else
            check_ok "$t"
        fi
    done
}

check $@

if (( ko == 0 )) ; then
    echo "$ok/$# SUCCESS"
else
    echo "$ko/$# FAILURES"
    rm -f ./cz
fi

exit $ko

# EOF
