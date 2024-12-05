NAME = a.out
CC ?= gcc
CINC = -I.
CSTD = -std=c23
CFLAGS = #-Wall -Werror -pedantic
LDFLAGS = -static -lc -lcsptr

all: $(NAME)

$(NAME):
	$(CC) $(CSTD) $(CINC) $(CFLAGS) *.c $(LDFLAGS)

run: $(NAME)
	@./$(NAME)

re: clean
	@make -B

clean:
	@rm -vf $(NAME)
