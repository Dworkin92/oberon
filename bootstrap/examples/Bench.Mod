MODULE Bench;
IMPORT Out, SYSTEM;

(* dispatch-heavy benchmark: tight loop of mixed 64-bit arithmetic.
   Not part of tests/run_tests.sh (TICKS output is non-deterministic);
   run manually: obc.exe examples/Bench.Mod && obvm.exe examples/Bench.obc *)

VAR i, n: INTEGER;
    acc, t0, t1: LONGINT;

BEGIN
  n := 20000000;
  acc := 0;
  t0 := SYSTEM.TICKS();
  i := 0;
  WHILE i < n DO
    acc := acc + i * 3 - (i DIV 7) + (i MOD 11);
    INC(i)
  END;
  t1 := SYSTEM.TICKS();
  Out.String("acc="); Out.Long(acc, 0); Out.Ln;
  Out.String("ticks="); Out.Long(t1 - t0, 0); Out.Ln
END Bench.
