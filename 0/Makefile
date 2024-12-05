NAME = czc
CC = gcc
CFLAGS = -Wall -Werror -pedantic -I.
LDFLAGS = -static -lc

all: $(NAME)

$(NAME):
	$(CC) $(CFLAGS) *.c $(LDFLAGS) -o $(NAME)

re: clean
	@make -B

clean:
	@rm -vf $(NAME)
