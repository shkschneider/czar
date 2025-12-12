#!/usr/bin/env bash

set +e
./build.sh || exit 1

[[ $# -ge 1 ]] || set -- tests/*.cz
mkdir -p ./build

ok=0
ko=0
for f in $@ ; do
    n=$f
    n=${n##*/}
    n=${n%@*}
    r=$f
    r=${r##*@}
    r=${r%.*}
    echo -n "- tests/$n..."
    if [[ ! $r =~ ^[0-9]+$ ]] ; then
        r=-1
    fi
    ./cz build $f -o ./build/$n >/dev/null 2>/tmp/cz
    if [[ ! -x ./build/$n ]] ; then
        echo " ERROR:"
        cat /tmp/cz >&2
        (( ko += 1 ))
    else
        ./build/$n >/dev/null 2>/tmp/cz
        e=$?
        if [[ $e -ne $r ]] ; then
            echo " FAILURE: $r vs $e"
            (( ko += 1 ))
        else
            [[ $e -ne 134 ]] && echo " SUCCESS: $r"
            (( ok += 1 ))
        fi
        rm -f ./build/$n
    fi
    rm -f /tmp/cz
done
echo "OK=$ok KO=$ko"

[[ $ko -gt 0 ]] && rm -f ./cz

exit $ko

# EOF
