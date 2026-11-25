MODULE Control;
IMPORT Out;

VAR i, sum: INTEGER;
    c: CHAR;

PROCEDURE Classify(n: INTEGER): INTEGER;
BEGIN
  CASE n OF
    0: RETURN 100
  | 1..9: RETURN 10 + n
  | 10, 20, 30: RETURN 1
  ELSE RETURN 0
  END
END Classify;

BEGIN
  (* WHILE *)
  i := 1; sum := 0;
  WHILE i <= 100 DO
    sum := sum + i;
    INC(i)
  END;
  Out.String("sum 1..100 = "); Out.Int(sum, 6); Out.Ln;

  (* REPEAT *)
  i := 10;
  REPEAT DEC(i) UNTIL i = 0;
  Out.String("repeat i = "); Out.Int(i, 3); Out.Ln;

  (* FOR with BY, downwards *)
  FOR i := 10 TO 1 BY -3 DO Out.Int(i, 4) END;
  Out.Ln;

  (* CASE on char *)
  FOR c := 'a' TO 'e' DO
    CASE c OF
      'a', 'e': Out.String("vowel ")
    | 'b'..'d': Out.String("cons. ")
    END;
    Out.Char(c); Out.String(" ")
  END;
  Out.Ln;

  (* CASE on int via function *)
  FOR i := 0 TO 12 DO
    IF i MOD 4 = 0 THEN Out.Int(Classify(i), 5) END
  END;
  Out.Ln
END Control.
