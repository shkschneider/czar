#!/usr/bin/env bash

set +e
./build.sh || exit 1

ok=0
ko=0

# First pass: tests that should succeed (exit 0)
echo "Running tests/ok (expected to pass)..."
for f in tests/ok/*.cz ; do
    n=${f##*/}
    echo -n "- $n..."
    o=${f/.cz/.out}
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
            [[ $e -eq 134 ]] || { # core dump (wanted crash?)
                echo " FAILURE: $e"
                (( ko += 1 ))
            }
        }
        rm -f ./$o
    fi
    rm -f /tmp/cz
done

# Second pass: tests that should fail compilation (exit non-zero)
echo ""
echo "Running tests/ko (expected to fail compilation)..."
for f in tests/ko/*.cz ; do
    n=${f##*/}
    echo -n "- $n..."
    ./cz build $f >/dev/null 2>/tmp/cz
    if [[ $? -ne 0 ]] ; then
        echo " SUCCESS (failed as expected)"
        (( ok += 1 ))
    else
        echo " ERROR (should have failed compilation):"
        cat /tmp/cz >&2
        (( ko += 1 ))
    fi
    rm -f /tmp/cz
done

echo ""
echo "OK=$ok KO=$ko"

[[ $ko -gt 0 ]] && rm -f ./cz

exit $ko

# EOF
