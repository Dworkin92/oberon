MODULE UseMath;
IMPORT Out, MathLib;

VAR i: INTEGER;
    t: ARRAY 4 OF INTEGER;

BEGIN
  Out.String("Square(12) = "); Out.Int(MathLib.Square(12), 5); Out.Ln;
  Out.String("GCD(1071, 462) = "); Out.Int(MathLib.GCD(1071, 462), 3); Out.Ln;
  Out.String("SumTo(100) = "); Out.Int(MathLib.SumTo(100), 6); Out.Ln;
  Out.String("MathLib.calls = "); Out.Int(MathLib.calls, 2); Out.Ln;
  (* open array across modules: ARRAY 4 OF INTEGER -> ARRAY OF INTEGER *)
  FOR i := 0 TO 3 DO t[i] := (i + 1) * 10 END;
  Out.String("SumArr(t) = "); Out.Int(MathLib.SumArr(t), 4); Out.Ln   (* 100 *)
END UseMath.
