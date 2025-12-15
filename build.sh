#!/usr/bin/env bash

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
WHITE="\e[0m"

r=0
echo "[CHECK] ..."
for dep in git pkg-config luajit nm ar cc ; do
    echo -n "- $dep: "
    path=$(command -v $dep 2>/dev/null)
    if [[ -n "$path" ]] ; then
        echo "$path"
    else
        echo -e $RED"MISSING"$WHITE
        (( r += 1))
    fi
done
(( r == 0 )) || exit 1

set -e

OUT="cz"
CFLAGS="$(pkg-config --cflags luajit 2>/dev/null) -O2"

# Check if luastatic is available for static linking
if command -v luastatic >/dev/null 2>&1; then
    # Note: luastatic is a tool for creating static Lua binaries.
    echo "[LUASTATIC] $(command -v luastatic) -> static"
    # When statically linking LuaJIT, the linker will produce a dlopen warning
    # because LuaJIT's FFI uses dlopen for dynamic library loading. This is
    # expected LuaJIT behavior and does not indicate a build failure.
    LDFLAGS="-static -L. -L./build -Wl,\
--whole-archive -lczar -Wl,\
--no-whole-archive -Wl,\
-E $(pkg-config --libs luajit 2>/dev/null) -lm -ldl -s"
else
    echo -e $YELLOW"[LUASTATIC] null -> dynamic"$WHITE
    LDFLAGS="-L. -L./build -Wl,\
--whole-archive -lczar -Wl,\
--no-whole-archive -Wl,\
-E $(pkg-config --libs luajit 2>/dev/null) -lm -ldl -s"
fi

SOURCES=(
    main.lua
    lexer/init.lua
    parser/init.lua
    typechecker/init.lua
    typechecker/resolver.lua
    typechecker/inference.lua
    typechecker/mutability.lua
    lowering/init.lua
    analysis/init.lua
    codegen/init.lua
    codegen/types.lua
    codegen/memory.lua
    codegen/functions.lua
    codegen/statements.lua
    codegen/expressions.lua
    generate.lua
    assemble.lua
    build.lua
    run.lua
    errors.lua
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
cc $CFLAGS -o ./$OUT ./build/main.c $LDFLAGS
echo -e "[CZ] "$GREEN$(file -b ./$OUT)$WHITE

#install -m 755 ./$(OUT) /usr/local/bin/cz
rm -rf ./build
