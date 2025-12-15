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
    echo -n "- tests/$n..."
    ./cz build $f -o ./build/$n >/dev/null 2>/tmp/cz
    if [[ ! -x ./build/$n ]] ; then
        echo " ERROR:"
        cat /tmp/cz >&2
        (( ko += 1 ))
    else
        ./build/$n >/dev/null 2>/tmp/cz && {
            echo " SUCCESS"
            (( ok += 1 ))
        } || {
            e=$?
            [[ $e -eq 134 ]] || { # core dump (wanted crash?)
                echo " FAILURE: $e"
                (( ko += 1 ))
            }
        }
        rm -f ./build/$n
    fi
    rm -f /tmp/cz
done
echo "OK=$ok KO=$ko"

[[ $ko -gt 0 ]] && rm -f ./cz

exit $ko

# EOF
