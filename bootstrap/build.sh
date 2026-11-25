#!/bin/bash
# Build the Oberon-07 bytecode toolchain (obc / obvm / obdis).
# Requires gcc (MinGW on Windows). A Makefile is also provided for GNU make.
cd "$(dirname "$0")" || exit 1
CC=${CC:-gcc}
CFLAGS="-O2 -std=gnu11 -Wall"
set -e
$CC $CFLAGS -o obc.exe   src/obc.c   src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm
$CC $CFLAGS -o obvm.exe  src/obvm.c  src/ob.c src/model.c src/module.c src/rt.c src/vm.c -lm
$CC $CFLAGS -o obdis.exe src/obdis.c src/ob.c src/model.c src/module.c -lm
$CC $CFLAGS -o ob2c.exe   src/ob2c.c   src/ob.c src/model.c src/module.c -lm
echo "built: obc.exe obvm.exe obdis.exe ob2c.exe"
