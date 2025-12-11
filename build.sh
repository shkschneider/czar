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
LDFLAGS="-L. -Wl,\
--whole-archive -lczar -Wl,\
--no-whole-archive -Wl,\
-E $(pkg-config --libs luajit 2>/dev/null) -lm -ldl -s" # TODO -static

SOURCES=(main.lua lexer.lua parser.lua codegen.lua)
LIBRARY=libczar.a

for src in ${SOURCES[@]} ; do
    obj="$(basename $src .lua).o"
    echo "[LUAJIT] $src -> $obj"
    luajit -b $src $obj
done

echo -n "[NM] main.h"
shopt -s extglob
echo "// Auto-generated" > main.h
echo "#include <stddef.h>" >> main.h
for src in ${SOURCES[@]} ; do
    name="$(basename $src .lua)"
    obj="$name.o"
    size=$(nm -S $obj | grep luaJIT_BC | awk '{print "0x" $2}')
    echo "const size_t luaJIT_BC_${name}_size = $size;" >> main.h
    echo -n " ${size/0x+(0)/0x}"
done
echo

echo "[AR]" *.o "-> $LIBRARY"
ar rcs $LIBRARY *.o

echo "[CC] main.c -lczar ..."
echo -e "\t$CFLAGS"
echo -e "\t$LDFLAGS"
cc $CFLAGS -o $OUT main.c $LDFLAGS
echo -n "[CZ] " ; file -b ./$OUT

#install -m 755 ./$(OUT) /usr/local/bin/cz
