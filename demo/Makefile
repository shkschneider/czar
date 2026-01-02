# Business as usual
CC        ?= cc
CFLAGS     = -Wall -Wextra -std=c11 -O2
LDFLAGS    = -lc
OUT       ?= a.out

#            remember to filter-out generated C!
SOURCES_C  = $(filter-out %.pp.c,$(wildcard *.c))
SOURCES_CZ = $(wildcard *.cz)
OBJECTS    = $(SOURCES_C:.c=.o) $(SOURCES_CZ:.cz=.pp.o)

all: $(OUT)

# Using CZar, you'll just need to add this:
%.pp.c: %.cz
	@cp $< $<.c
	$(CC) -E $<.c -o $@
	@rm -f $<.c

# Compilation as usual
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Linking as usual
$(OUT): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $(OUT)

clean:
	@rm -vf ./*.pp.* ./*.o ./*.out
