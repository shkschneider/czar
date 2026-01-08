# Business as usual
CC        ?= cc
CZ        ?= ../../build/cz
CFLAGS     = -std=c11 -Wall -Wextra -O2 -I.
LDFLAGS    = -lc
OUT       ?= a.out

#            remember to filter-out generated C!
SOURCES_C  = $(filter-out %.cz.c,$(wildcard *.c))
SOURCES_CZ = $(wildcard */*.cz) $(wildcard *.cz)
OBJECTS    = $(SOURCES_C:.c=.o) $(SOURCES_CZ:.cz=.cz.o)

all: $(CZ) $(OUT)
	@./$(OUT)

# CZar
.SUFFIXES:
%.cz.c: %.cz
	$(CZ) $<

# Compilation as usual
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Linking as usual
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)

clean:
	@find . -type f \( -name "*.h" -o -name "*.cz.c" \) -exec rm -vf {} \;
	@find . -type f \( -name "*.o" -o -executable \) -exec rm -vf {} \;
