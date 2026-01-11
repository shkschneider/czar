OUT ?= a.out
SRC = $(wildcard *.c)
OBJ = $(SRC:.c=.o)
CFLAGS = -Wall -Wextra -Werror
LDFLAGS = -I../../dist -L../../dist -l:libczar.a

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT): $(OBJ)
	$(CC) $(OBJ) $(LDFLAGS) -o $(OUT)
	./$(OUT)

clean:
	@rm -vf $(OBJ) $(OUT)
