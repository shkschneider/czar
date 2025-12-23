#!/usr/bin/env bash

OUT="dist/cz"
STATIC=${STATIC:-false}
VERBOSE=${VERBOSE:-false}
RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
WHITE="\e[0m"

r=0
deps=(git pkg-config luajit nm ar cc stat file)
echo "[CHECK] ${deps[@]} ..."
for dep in ${deps[@]} ; do
    path=$(command -v $dep 2>/dev/null)
    if [[ -n "$path" ]] ; then
        [[ $VERBOSE == true ]] && echo "- $dep: $path"
    else
        echo -e "- $dep: "$RED"MISSING"$WHITE >&2
        (( r += 1))
    fi
done
(( r == 0 )) || exit $r
pkg-config --exists luajit || {
    echo -e "ERROR: "$RED"MISSING luajit"$WHITE >&2
    exit 1
}

CFLAGS="$(pkg-config --cflags luajit 2>/dev/null) -O2"
LDFLAGS="-L./build -lczar -Wl"

dynamic() {
    echo -e $YELLOW"[LUA] dynamic"$WHITE
    LIBS="$(pkg-config --libs luajit 2>/dev/null)"
    LDFLAGS="-L./build -Wl,\
--whole-archive -lczar -Wl,--no-whole-archive -Wl,\
-E $LIBS -s"
    return 0
}

static() {
    echo -e $YELLOW"[LUA] static"$WHITE
    LIBS="$(pkg-config --static luajit 2>/dev/null || echo -- '-lluajit')"
    if [[ ! -f ./build/libluajit.a ]] ; then
        [[ -d /tmp/luajit ]] && rm -rf /tmp/luajit
        echo "luajit.org/git/luajit.git..."
        git clone -q https://luajit.org/git/luajit.git /tmp/luajit || return 1
        echo "make..."
        make -C /tmp/luajit/src >/dev/null || return 1
        [[ -e /tmp/luajit/src/libluajit.a ]] || return 1
        echo "/tmp/luajit/src/libluajit.a"
        mkdir -p ./build
        mv /tmp/luajit/src/libluajit.a ./build/ || return 1
        rm -rf /tmp/luajit
    fi
    # When statically linking LuaJIT, the linker will produce a dlopen warning
    # because LuaJIT's FFI uses dlopen for dynamic library loading.
    LDFLAGS="-L./build -lluajit -Wl,\
--whole-archive -lczar -Wl,--no-whole-archive -Wl,\
-E -lm -ldl -static"
    return 0
}

set -e
SOURCES=($(cd ./src && find * -type f -name "*.lua"))
LIBRARY=libczar.a

mkdir -p ./build ./dist
[[ $VERBOSE == false ]] && echo "[LUAJIT] *.lua (${#SOURCES[@]}) ..."
for src in ${SOURCES[@]} ; do
    # For module naming, use just the base filename (without directory)
    # unless it's in a subdirectory like lexer/init.lua, parser/init.lua, etc.
    # In those cases, we want lexer_init, parser_init, etc.
    name=${src//\//_}
    name="$(basename $name .lua)"
    # Special case: if the module is in bin/, we want just the base name
    # e.g., bin/main.lua -> main, not bin_main
    if [[ $src == bin/* ]]; then
        name="$(basename $src .lua)"
    fi
    obj="$name.o"
    [[ $VERBOSE == true ]] && echo "[LUAJIT] $src -> $obj"
    luajit -b -n $name ./src/$src ./build/$obj # bytecode module-name
done

if [[ $STATIC == true ]] ; then
    static || dynamic
else
    dynamic
fi

echo -n "[NM] main.h"
echo "// Auto-generated" > ./build/main.h
echo "#include <stddef.h>" >> ./build/main.h
shopt -s extglob
for src in ${SOURCES[@]} ; do
    name="$(basename ${src//\//_} .lua)"
    # Special case: if the module is in bin/, we want just the base name
    if [[ $src == bin/* ]]; then
        name="$(basename $src .lua)"
    fi
    obj="$name.o"
    size=$(nm -S ./build/$obj | grep luaJIT_BC | awk '{print "0x" $2}')
    echo "const size_t luaJIT_BC_${name}_size = $size;" >> ./build/main.h
    echo -n " ${size/0x+(0)/0x}"
done
echo

echo "[AR] *.o -> $LIBRARY"
#for o in ./build/*.o ; do echo "- ${o##*/}" ; done
ar crs ./build/$LIBRARY ./build/*.o # create replace act-as-ranlib

echo "[CC] main.c -lczar ... -> $OUT"
echo -e "\t$CFLAGS"
echo -e "\t$LDFLAGS"
cp ./src/bin/main.c ./build/main.c
cc $CFLAGS -o ./$OUT ./build/main.c $LDFLAGS
echo -e "[CZ] "$GREEN$(du -h ./$OUT 2>/dev/null)$WHITE" "$(file -b ./$OUT 2>/dev/null )

#install -m 755 ./$(OUT) /usr/local/bin/cz
rm -rf ./build
