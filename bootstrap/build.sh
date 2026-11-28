#!/bin/bash
# Build the Oberon-07 toolchain into build/bin (our local OBERON_HOME) and
# populate build/lib with the library modules (sources + precompiled .obc).
#
# Install layout (see docs/LANGAGE.md / journal):
#   build/bin/  obc.exe obvm.exe obdis.exe ob2c.exe  (+ sqlite3.dll if present)
#   build/lib/  lib modules (*.Mod + *.obc)
# OBERON_HOME defaults to the exe dir with a trailing /bin stripped -> build/,
# so build/lib is found automatically via $OBERON_HOME/lib.
cd "$(dirname "$0")" || exit 1
CC=${CC:-gcc}
CFLAGS="-O2 -std=gnu11 -Wall"
BIN=build/bin
LIB=build/lib
mkdir -p "$BIN" "$LIB"
set -e
# FFI: src/ffi_glue.c (LoadLibrary/GetProcAddress + CALLC + GETENV/EXEPATH) is linked
# into obvm.exe and the native ob2c binaries; DLLs (e.g. sqlite3.dll) are loaded at
# runtime via SYSTEM.LOADLIB — no static linking of external libraries.
$CC $CFLAGS -o $BIN/obc.exe   src/obc.c   src/ob.c src/lexer.c src/model.c src/module.c src/parser.c -lm
$CC $CFLAGS -o $BIN/obvm.exe  src/obvm.c  src/ob.c src/model.c src/module.c src/rt.c src/ffi_glue.c src/vm.c -lm
$CC $CFLAGS -o $BIN/obdis.exe src/obdis.c src/ob.c src/model.c src/module.c -lm
$CC $CFLAGS -o $BIN/ob2c.exe   src/ob2c.c   src/ob.c src/model.c src/module.c -lm
# local install: library modules -> build/lib (copy sources, precompile .obc)
rm -f $LIB/*.Mod $LIB/*.obc 2>/dev/null
for m in ../lib/*.Mod; do
  [ -e "$m" ] || continue
  cp "$m" $LIB/
  $BIN/obc.exe "$LIB/$(basename "$m")" > /dev/null
done
# sqlite3.dll next to the executables so SYSTEM.LOADLIB("sqlite3.dll") finds it
if [ -f /c/Local/Tools/sqlite3/sqlite3.dll ]; then cp /c/Local/Tools/sqlite3/sqlite3.dll $BIN/; fi
echo "built: $BIN/{obc,obvm,obdis,ob2c}.exe  +  $LIB/ (lib modules)"
