# Build system for CZar C semantic authority layer
CC     ?= cc
CFLAGS  = -std=c11 -Wall -Wextra -pedantic -O2
LDFLAGS = -lc
OUT    ?= build/cz

SOURCES = $(wildcard ./bin/*.c)
OBJECTS = $(patsubst ./bin/%.c,./build/%.o,$(SOURCES))

all: $(OUT)

$(OUT): $(OBJECTS) | build
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)

./build/%.o: ./bin/%.c
	$(CC) $(CFLAGS) -c $< -o $@

build:
	mkdir -p ./build

clean:
	@rm -rvf ./build
	@rm -vf ./tests/*.pp.* ./tests/*.o ./tests/*.out
