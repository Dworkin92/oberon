CC = gcc
CFLAGS = -O2 -Wall -Wextra -std=gnu11 -g
SRC = src/ob.c src/lexer.c src/model.c src/module.c src/parser.c src/vm.c

all: obc.exe obvm.exe obdis.exe ob2c.exe

obc.exe: $(SRC) src/obc.c
	$(CC) $(CFLAGS) -o $@ src/obc.c src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm

obvm.exe: src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c src/obvm.c
	$(CC) $(CFLAGS) -o $@ src/obvm.c src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c -lm

obdis.exe: src/ob.c src/model.c src/module.c src/obdis.c
	$(CC) $(CFLAGS) -o $@ src/obdis.c src/ob.c src/model.c src/module.c -lm

ob2c.exe: src/ob.c src/model.c src/module.c src/ob2c.c
	$(CC) $(CFLAGS) -o $@ src/ob2c.c src/ob.c src/model.c src/module.c -lm

clean:
	rm -f obc.exe obvm.exe obdis.exe ob2c.exe examples/*.obc ../lib/*.obc ../selfhost/*.obc

.PHONY: all clean
