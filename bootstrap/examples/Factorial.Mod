MODULE Factorial;
IMPORT Out;

PROCEDURE Fact(n: INTEGER): INTEGER;
BEGIN
  IF n <= 1 THEN RETURN 1 END;
  RETURN n * Fact(n - 1)
END Fact;

VAR i: INTEGER;
BEGIN
  FOR i := 0 TO 10 DO
    Out.String("fact("); Out.Int(i, 2); Out.String(") = "); Out.Int(Fact(i), 12); Out.Ln
  END
END Factorial.
