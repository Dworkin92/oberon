CC = /c/Local/Tools/mingw64-16.2.0/bin/gcc.exe
CFLAGS = -O2 -Wall -Wextra -std=gnu11 -g
BIN = build/bin
LIB = build/lib

all: $(BIN)/obc.exe $(BIN)/obvm.exe $(BIN)/obdis.exe $(BIN)/ob2c.exe install-lib

$(BIN):
	mkdir -p $(BIN) $(LIB)

$(BIN)/obc.exe: src/obc.c src/ob.c src/lexer.c src/model.c src/module.c src/parser.c | $(BIN)
	$(CC) $(CFLAGS) -o $@ src/obc.c src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm

$(BIN)/obvm.exe: src/obvm.c src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c | $(BIN)
	$(CC) $(CFLAGS) -o $@ src/obvm.c src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c -lm

$(BIN)/obdis.exe: src/obdis.c src/ob.c src/model.c src/module.c | $(BIN)
	$(CC) $(CFLAGS) -o $@ src/obdis.c src/ob.c src/model.c src/module.c -lm

$(BIN)/ob2c.exe: src/ob2c.c src/ob.c src/model.c src/module.c | $(BIN)
	$(CC) $(CFLAGS) -o $@ src/ob2c.c src/ob.c src/model.c src/module.c -lm

install-lib: $(BIN)/obc.exe
	rm -f $(LIB)/*.Mod $(LIB)/*.obc 2>/dev/null
	for m in ../lib/*.Mod; do cp "$$m" $(LIB)/ && $(BIN)/obc.exe $(LIB)/$$(basename $$m) > /dev/null; done
	-[ -f /c/Local/Tools/sqlite3/sqlite3.dll ] && cp /c/Local/Tools/sqlite3/sqlite3.dll $(BIN)/

clean:
	rm -f $(BIN)/*.exe $(LIB)/*.obc $(LIB)/*.Mod examples/*.obc ../lib/*.obc ../selfhost/*.obc

.PHONY: all clean install-lib
