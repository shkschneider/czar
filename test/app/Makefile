CZ      ?= ../../dist/cz
CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -I.
LDFLAGS ?= -lc
OUT     := a.out

SOURCES_C  := $(filter-out %.cz.c,$(wildcard *.c))
SOURCES_CZ := $(wildcard */*.cz) $(wildcard *.cz)
OBJECTS    := $(SOURCES_CZ:.cz=.cz.o) $(SOURCES_C:.c=.o)

all: $(CZ) $(OUT)
	./$(OUT)

# CZar
.PRECIOUS: $(SOURCES_CZ:.cz=.cz.h) $(SOURCES_CZ:.cz=.cz.c)
%.cz.c %.cz.h &: %.cz
	$(CZ) $<
# All .cz.o files depend on all .cz.h files being generated (for auto-includes)
%.cz.o: %.cz.c %.cz.h $(SOURCES_CZ:.cz=.cz.h)
	$(CC) $(CFLAGS) -c $< -o $@
.SUFFIXES:

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)

clean:
	@find . -type f \( -name "*.cz.h" -o -name "*.cz.c" \) -exec rm -vf {} \;
	@find . -type f \( -name "*.o" -o -executable \) -exec rm -vf {} \;
.PHONY: all clean
