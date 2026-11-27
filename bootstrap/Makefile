CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=gnu11 -g
SRC = src/ob.c src/lexer.c src/model.c src/module.c src/parser.c src/vm.c

all: obc.exe obvm.exe obdis.exe ob2c.exe

obc.exe: $(SRC) src/obc.c
	$(CC) $(CFLAGS) -o $@ src/obc.c src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm

ext/sqlite/sqlite3.o: ext/sqlite/sqlite3.c ext/sqlite/sqlite3.h
	$(CC) -O2 -std=gnu11 -w -c ext/sqlite/sqlite3.c -o $@

obvm.exe: src/ob.c src/model.c src/module.c src/rt.c src/sqlite_glue.c src/vm.c src/obvm.c ext/sqlite/sqlite3.o
	$(CC) $(CFLAGS) -o $@ src/obvm.c src/ob.c src/model.c src/module.c src/rt.c src/sqlite_glue.c src/vm.c ext/sqlite/sqlite3.o -lm

obdis.exe: src/ob.c src/model.c src/module.c src/obdis.c
	$(CC) $(CFLAGS) -o $@ src/obdis.c src/ob.c src/model.c src/module.c -lm

ob2c.exe: src/ob.c src/model.c src/module.c src/ob2c.c
	$(CC) $(CFLAGS) -o $@ src/ob2c.c src/ob.c src/model.c src/module.c -lm

clean:
	rm -f obc.exe obvm.exe obdis.exe ob2c.exe examples/*.obc ../lib/*.obc ../selfhost/*.obc

.PHONY: all clean
