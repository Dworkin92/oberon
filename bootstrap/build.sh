#!/bin/bash
# Build the Oberon-07 bytecode toolchain (obc / obvm / obdis).
# Requires gcc (MinGW on Windows). A Makefile is also provided for GNU make.
cd "$(dirname "$0")" || exit 1
CC=${CC:-gcc}
CFLAGS="-O2 -std=gnu11 -Wall"
set -e
# FFI : src/ffi_glue.c (LoadLibrary/GetProcAddress + CALLC) est linké dans obvm.exe
# et dans les binaires natifs ob2c ; les DLL (ex. sqlite3.dll) sont chargées à
# l'exécution via SYSTEM.LOADLIB — aucun link statique de bibliothèque externe.
$CC $CFLAGS -o obc.exe   src/obc.c   src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm
$CC $CFLAGS -o obvm.exe  src/obvm.c  src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c -lm
$CC $CFLAGS -o obdis.exe src/obdis.c src/ob.c src/model.c src/module.c -lm
$CC $CFLAGS -o ob2c.exe   src/ob2c.c   src/ob.c src/model.c src/module.c -lm
echo "built: obc.exe obvm.exe obdis.exe ob2c.exe"
