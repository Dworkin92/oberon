#!/bin/bash
# Test suite: compile and run each example, compare with expected output.
# usage: tests/run_tests.sh   (from the project root)
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
BIN=build/bin
export OBERON_HOME="$ROOT/build"   # exercise the OBERON_HOME/lib search path
mkdir -p tests/expected tests/out
rm -f ../lib/*.obc   # force recompilation of library modules from lib/*.Mod
# FFI : les binaires natifs linkent src/ffi_glue.c (LoadLibrary/GetProcAddress/CALLC) ;
# la DLL sqlite3.dll est chargee a l'execution (chemin absolu de repli dans lib/Sqlite.Mod).
FFI_O="src/ffi_glue.c"
pass=0; fail=0

# build the Oberon-written VM once (selfhost/VM.Mod -> ../selfhost/VM.obc)
if [ ! -f ../selfhost/VM.obc ] || [ ../selfhost/VM.Mod -nt ../selfhost/VM.obc ]; then
  $BIN/obc.exe ../selfhost/VM.Mod > /dev/null 2>&1 || echo "WARN: cannot compile ../selfhost/VM.Mod (VM phases skipped)"
fi
HAVE_VM=$([ -f ../selfhost/VM.obc ] && echo 1 || echo 0)
# and its native version: ob2c + gcc (étape 5) -> tests/out/vm_native.exe
HAVE_VMN=0
if [ "$HAVE_VM" = 1 ]; then
  if $BIN/ob2c.exe ../selfhost/VM.obc -o tests/out/VM.gen.c 2>/dev/null \
     && gcc -O2 -std=gnu11 -w -Isrc -o tests/out/vm_native.exe tests/out/VM.gen.c src/rt.c src/ob.c src/model.c src/module.c $FFI_O -lm 2>/dev/null; then
    HAVE_VMN=1
  else
    echo "WARN: native VM.Mod build failed (VMN phase skipped)"
  fi
fi

run_test() {
  local name=$1; local input=$2; shift 2   # extra args = program args (SYSTEM.ARGV)
  rm -f "examples/$name.obc"
  if ! $BIN/obc.exe "examples/$name.Mod" > "tests/out/$name.compile.log" 2>&1; then
    echo "FAIL $name (compile)"; cat "tests/out/$name.compile.log"; fail=$((fail+1)); return
  fi
  if [ -n "$input" ]; then
    printf '%b' "$input" | $BIN/obvm.exe "examples/$name.obc" "$@" > "tests/out/$name.txt" 2>&1
  else
    $BIN/obvm.exe "examples/$name.obc" "$@" > "tests/out/$name.txt" 2>&1
  fi
  local rc=$?
  # normalize CRLF
  sed -i 's/\r$//' "tests/out/$name.txt"
  if [ ! -f "tests/expected/$name.txt" ]; then
    cp "tests/out/$name.txt" "tests/expected/$name.txt"
    echo "NEW  $name (expected output recorded)"
    pass=$((pass+1)); return
  fi
  if diff -q "tests/expected/$name.txt" "tests/out/$name.txt" > /dev/null; then
    echo "PASS $name"
    pass=$((pass+1))
  else
    echo "FAIL $name (output differs)"; diff "tests/expected/$name.txt" "tests/out/$name.txt" | head -10
    fail=$((fail+1))
  fi
}

# C-backend phase: transpile the .obc to C (ob2c), compile with gcc, run, diff vs the same reference
run_ctest() {
  local name=$1; local input=$2; shift 2
  if ! $BIN/ob2c.exe "examples/$name.obc" -o "tests/out/$name.gen.c" 2> "tests/out/$name.ob2c.log"; then
    echo "FAIL-C $name (ob2c)"; cat "tests/out/$name.ob2c.log"; fail=$((fail+1)); return
  fi
  if ! gcc -O2 -std=gnu11 -w -Isrc -o "tests/out/$name.native.exe" "tests/out/$name.gen.c" src/rt.c src/ob.c src/model.c src/module.c $FFI_O -lm 2> "tests/out/$name.gcc.log"; then
    echo "FAIL-C $name (gcc)"; head -5 "tests/out/$name.gcc.log"; fail=$((fail+1)); return
  fi
  if [ -n "$input" ]; then
    printf '%b' "$input" | "tests/out/$name.native.exe" "examples/$name.obc" "$@" > "tests/out/$name.native.txt" 2>&1
  else
    "tests/out/$name.native.exe" "examples/$name.obc" "$@" > "tests/out/$name.native.txt" 2>&1
  fi
  sed -i 's/\r$//' "tests/out/$name.native.txt"
  if diff -q "tests/expected/$name.txt" "tests/out/$name.native.txt" > /dev/null; then
    echo "PASS-C $name"
    pass=$((pass+1))
  else
    echo "FAIL-C $name (output differs)"; diff "tests/expected/$name.txt" "tests/out/$name.native.txt" | head -10
    fail=$((fail+1))
  fi
}

# VM-in-Oberon phase: run the example through selfhost/VM.Mod executed by obvm
run_vmtest() {
  local name=$1; local input=$2; shift 2
  if [ "$HAVE_VM" != 1 ]; then return; fi
  if [ -n "$input" ]; then
    printf '%b' "$input" | $BIN/obvm.exe ../selfhost/VM.obc "examples/$name.obc" "$@" > "tests/out/$name.vm.txt" 2>&1
  else
    $BIN/obvm.exe ../selfhost/VM.obc "examples/$name.obc" "$@" > "tests/out/$name.vm.txt" 2>&1
  fi
  sed -i 's/\r$//' "tests/out/$name.vm.txt"
  if diff -q "tests/expected/$name.txt" "tests/out/$name.vm.txt" > /dev/null; then
    echo "PASS-VM $name"
    pass=$((pass+1))
  else
    echo "FAIL-VM $name (output differs)"; diff "tests/expected/$name.txt" "tests/out/$name.vm.txt" | head -10
    fail=$((fail+1))
  fi
}

# native VM.Mod phase (étape 5): VM.Mod transpilé en C par ob2c, compilé par gcc
run_vmntest() {
  local name=$1; local input=$2; shift 2
  if [ "$HAVE_VMN" != 1 ]; then return; fi
  if [ -n "$input" ]; then
    printf '%b' "$input" | "tests/out/vm_native.exe" ../selfhost/VM.obc "examples/$name.obc" "$@" > "tests/out/$name.vmn.txt" 2>&1
  else
    "tests/out/vm_native.exe" ../selfhost/VM.obc "examples/$name.obc" "$@" > "tests/out/$name.vmn.txt" 2>&1
  fi
  sed -i 's/\r$//' "tests/out/$name.vmn.txt"
  if diff -q "tests/expected/$name.txt" "tests/out/$name.vmn.txt" > /dev/null; then
    echo "PASS-VMN $name"
    pass=$((pass+1))
  else
    echo "FAIL-VMN $name (output differs)"; diff "tests/expected/$name.txt" "tests/out/$name.vmn.txt" | head -10
    fail=$((fail+1))
  fi
}

for m in Hello Factorial Arrays Records Sets Control CaseLabels OpenArr UseMath StringsDemo Nested Primes Sem Queens Longint FilesDemo DynArr RealConv WithDemo ProcVar Closure RecVar WhileElsif TypeCase CapDemo SqlDemo; do
  run_test "$m" ""
  run_ctest "$m" ""
  run_vmtest "$m" ""
  run_vmntest "$m" ""
done
run_test Echo '7\n2.5\nOberon\n';        run_ctest Echo '7\n2.5\nOberon\n';   run_vmtest Echo '7\n2.5\nOberon\n';   run_vmntest Echo '7\n2.5\nOberon\n'
run_test Bytes 'AB\000\377';             run_ctest Bytes 'AB\000\377';      run_vmtest Bytes 'AB\000\377';      run_vmntest Bytes 'AB\000\377'
run_test SysDemo '' alpha 42;            run_ctest SysDemo '' alpha 42;     run_vmtest SysDemo '' alpha 42;     run_vmntest SysDemo '' alpha 42
# LexDump : test du scanner Oberon selfhost/OCS.Mod (dump des tokens de Hello.Mod)
run_test LexDump '' examples/Hello.Mod; run_ctest LexDump '' examples/Hello.Mod; run_vmtest LexDump '' examples/Hello.Mod; run_vmntest LexDump '' examples/Hello.Mod
# SqlDemo passe par lib/Sqlite.Mod : binding PUR Oberon au-dessus du FFI SYSTEM
# (LOADLIB "sqlite3.dll" -> C:\Local\Tools\sqlite3\sqlite3.dll en repli, SYMBOL, CALLC).

echo "-----------------------------------"
echo "passed: $pass  failed: $fail"
[ $fail -eq 0 ]
