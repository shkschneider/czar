#!/usr/bin/env bash

r=0
echo "[CHECK] ..."
for dep in git pkg-config luajit nm ar cc ; do
    echo -n "- $dep: "
    path=$(command -v $dep 2>/dev/null)
    if [[ -n "$path" ]] ; then
        echo "$path"
    else
        echo "MISSING"
        (( r += 1))
    fi
done
(( r == 0 )) || exit 1

set -e

OUT=cz
CFLAGS="$(pkg-config --cflags luajit 2>/dev/null) \
-O2"
LDFLAGS="-static -L. -Wl,\
--whole-archive -lczar -Wl,\
--no-whole-archive -Wl,\
-E $(pkg-config --libs luajit 2>/dev/null) -lm -ldl -s"

SOURCES=(
    main.lua
    lexer/init.lua
    parser/init.lua
    codegen/init.lua
    codegen/types.lua
    codegen/memory.lua
    codegen/functions.lua
    codegen/statements.lua
    codegen/expressions.lua
    generate.lua assemble.lua build.lua run.lua
)

LIBRARY=libczar.a
mkdir -p ./build

for src in ${SOURCES[@]} ; do
    name=${src//\//_}
    name="$(basename $name .lua)"
    obj="$name.o"
    echo "[LUAJIT] $src -> $obj"
    luajit -b -n $name ./src/$src ./build/$obj # bytecode module-name
done

echo -n "[NM] main.h"
shopt -s extglob
echo "// Auto-generated" > ./build/main.h
echo "#include <stddef.h>" >> ./build/main.h
for src in ${SOURCES[@]} ; do
    name="$(basename ${src//\//_} .lua)"
    obj="$name.o"
    size=$(nm -S ./build/$obj | grep luaJIT_BC | awk '{print "0x" $2}')
    echo "const size_t luaJIT_BC_${name}_size = $size;" >> ./build/main.h
    echo -n " ${size/0x+(0)/0x}"
done
echo

echo "[AR] *.o -> $LIBRARY"
#for o in ./build/*.o ; do echo "- ${o##*/}" ; done
ar crs ./build/$LIBRARY ./build/*.o # create replace act-as-ranlib

cp ./src/main.c ./build/main.c
echo "[CC] main.c -lczar ..."
echo -e "\t$CFLAGS"
echo -e "\t$LDFLAGS"
cc $CFLAGS -o ./$OUT ./build/main.c -L./build $LDFLAGS
echo -n "[CZ] " ; file -b ./$OUT

set +e
rm -rf ./build
./$OUT run ./demo/main.cz >/dev/null 2>/tmp/cz \
    && echo "[DEMO] SUCCESS: $?" \
    || { echo "[DEMO] FAILURE: $?" >&2 ; cat /tmp/cz ; exit 1 ; }
rm -f ./a.out

#install -m 755 ./$(OUT) /usr/local/bin/cz
