MODULE MathLib;
(* exported library module: functions + exported variable *)

VAR calls*: INTEGER; (* exported global *)

PROCEDURE Square*(x: INTEGER): INTEGER;
BEGIN
  INC(calls);
  RETURN x * x
END Square;

PROCEDURE GCD*(a, b: INTEGER): INTEGER;
VAR t: INTEGER;
BEGIN
  WHILE b # 0 DO
    t := a MOD b;
    a := b;
    b := t
  END;
  RETURN a
END GCD;

PROCEDURE SumTo*(n: INTEGER): INTEGER;
BEGIN
  RETURN n * (n + 1) DIV 2
END SumTo;

(* open array param, exported: any ARRAY OF INTEGER, any length *)
PROCEDURE SumArr*(a: ARRAY OF INTEGER): INTEGER;
VAR i, t: INTEGER;
BEGIN
  t := 0;
  FOR i := 0 TO LEN(a, 0) - 1 DO t := t + a[i] END;
  RETURN t
END SumArr;

END MathLib.
