#!/usr/bin/env bash

set +e
./build.sh || exit 1

[[ $# -ge 1 ]] || set -- tests/*.cz

ok=0
ko=0
for f in $@ ; do
    n=$f
    n=${n##*/}
    n=${n%@*}
    echo -n "- tests/$n..."
    o=${f/.cz/.out}
    ./cz build $f -o $o >/dev/null 2>/tmp/cz
    if [[ ! -x $o ]] ; then
        echo " ERROR:"
        cat /tmp/cz >&2
        (( ko += 1 ))
    else
        ./$o >/dev/null 2>/tmp/cz && {
            echo " SUCCESS"
            (( ok += 1 ))
        } || {
            e=$?
            [[ $e -eq 134 ]] || { # core dump (wanted crash?)
                echo " FAILURE: $e"
                (( ko += 1 ))
            }
        }
        rm -f ./$o
    fi
    rm -f /tmp/cz
done
echo "OK=$ok KO=$ko"

[[ $ko -gt 0 ]] && rm -f ./cz

exit $ko

# EOF
