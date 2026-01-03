# Business as usual
CC        ?= cc
CZ        ?= ../build/cz
CFLAGS     = -std=c11 -Wall -Wextra -O2
LDFLAGS    = -lc
OUT       ?= a.out

#            remember to filter-out generated C!
SOURCES_C  = $(filter-out %.cz.c,$(wildcard *.c))
SOURCES_CZ = $(patsubst %.cz,%.cz.c,$(wildcard *.cz))
OBJECTS    = $(SOURCES_C:.c=.o) $(SOURCES_CZ:.c=.o)

all:
	@echo $(SOURCES_C) + $(SOURCES_CZ) -> $(OBJECTS) = $(OUT)
	$(MAKE) $(OUT)

# Using CZar, you'll just need to add this:
.SUFFIXES: # turn off implicit suffix rules (circular dependency)
%.cz.c: %.cz
	$(CZ) $< $@
%.cz.o: %.cz.c
	$(CC) $(CFLAGS) -c $< -o $@

# Compilation as usual
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Linking as usual
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)

clean:
	@rm -vf ./*.cz.c ./*.o ./*.out
