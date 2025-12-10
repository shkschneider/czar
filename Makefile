all:
	rm -f ./example.c
	lua main.lua ./example.cz > ./example.c
	cc ./example.c
	./a.out
	rm -f ./a.out
