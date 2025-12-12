/*
 * 99 bottles of beer in ansi c
 * by Bill Wein: bearheart@bearnet.com
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

void drink(int beers)
{
    char howmany[8], *s;
    s = beers != 1 ? "s" : "";
    printf("%d bottle%s of beer on the wall,\n", beers, s);
    printf("%d bottle%s of beeeeer . . . ,\n", beers, s);
    printf("Take one down, pass it around,\n");
    if (--beers) sprintf(howmany, "%d", beers); else strcpy(howmany, "No more");
    s = beers != 1 ? "s" : "";
    printf("%s bottle%s of beer on the wall.\n", howmany, s);
}

void main() {
    for(int beers = 9*9*9*9*9*9*9; beers; drink(beers--)) puts("");
    puts("\nTime to buy more beer!\n");
    exit(0);
}

