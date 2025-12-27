#!/usr/bin/env bash

set +e
OUT="cz"
if [[ -x ./$OUT ]] ; then
    echo "[CLEAN] ..."
    ./clean.sh >/dev/null
fi
./build.sh || exit 1

OK=0
KO=0
RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
WHITE="\e[0m"

# expected to exit 0
check_ok() {
    local i=$1
    local j=$2
    local f=$3
    echo -ne "\r[TEST] ($i/$j) $f..."
    local o=${f/.cz/.out}
    ./$OUT build $f -o $o >/dev/null 2>/tmp/cz
    if [[ ! -x $o ]] ; then
        echo -e $RED" ERROR:"$WHITE" "
        cat /tmp/cz >&2
        (( KO += 1 ))
    else
        ./$o >/dev/null 2>/tmp/cz && {
            echo -n " SUCCESS "
            (( OK += 1 ))
        } || {
            e=$?
            echo -e $RED" FAILURE: $e"$WHITE" "
            (( KO += 1 ))
        }
        rm -f ./dist/$o
    fi
    rm -f /tmp/cz
}

# expected to fail compilation (or exit non-zero)
check_ko() {
    local i=$1
    local j=$2
    local f=$3
    echo -ne "\r[TEST] ($i/$j) $f..."
    local o=${f/.cz/.out}
    ./$OUT build $f -o $o >/dev/null 2>/tmp/cz
    local e=$?
    if [[ $e -ne 0 ]] ; then
        echo -n " SUCCESS "
        (( OK += 1 ))
    else
        ./$o >/dev/null 2>/tmp/cz && {
            echo -e $RED" FAILURE"$WHITE" "
            (( KO += 1 ))
        } || {
            e=$?
            [[ $e -ne 134 ]] && echo -n " SUCCESS " # core dump
            (( OK += 1 ))
        }
        rm -f ./$o
    fi
    rm -f /tmp/cz
}

shopt -s nullglob
[[ $# -ge 1 ]] || set -- tests/ok/*.cz tests/ko/*.cz tests/*.cz

check() {
    local i=0
    for t in $@ ; do
        (( i += 1 ))
        p=${t%/*}
        p=${p##*/}
        if [[ $p == "ko" ]] ; then
            check_ko $i $# "$t"
        else
            check_ok $i $# "$t"
        fi
    done
}

check $@
echo

if (( KO == 0 )) ; then
    echo -e $GREEN"$OK/$# SUCCESS"$WHITE
else
    echo -e $RED"$KO/$# FAILURES"$WHITE
fi

exit $KO

# EOF
