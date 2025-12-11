#!/usr/bin/env bash

./build.sh || exit 1

[[ $# -eq 1 ]] || set -- tests/*.cz

ok=0
ko=0
for f in $@ ; do
    n=$f
    n=${n##*/}
    n=${n%:*}
    r=$f
    r=${r##*:}
    r=${r%.*}
    echo -n "tests/$n..."
    if [[ ! $r =~ ^[0-9]+$ ]] ; then
        r=0
    fi
    ./cz build $f -o /tmp/$n >/dev/null 2>/tmp/cz
    if [[ ! -f /tmp/$n ]] ; then
        echo " ERROR:"
        cat /tmp/cz >&2
        (( ko += 1 ))
    else
        /tmp/$n >/dev/null 2>/tmp/cz
        e=$?
        if [[ $e -ne $r ]] ; then
            echo " FAILURE: $r vs $e"
            (( ko += 1 ))
        else
            echo " SUCCESS: $r"
            (( ok += 1 ))
        fi
        rm -f /tmp/$n
    fi
    rm -f /tmp/cz
done
echo "OK=$ok KO=$ko"

exit $ko
# EOF
