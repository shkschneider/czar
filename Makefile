all:
	rm -f ./example.c
	lua5.4 main.lua ./example.cz > ./example.c
	cc ./example.c
	./a.out
	rm -f ./a.out
