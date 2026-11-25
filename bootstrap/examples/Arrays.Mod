MODULE Arrays;
IMPORT Out;

VAR a: ARRAY 10 OF INTEGER;
    m: ARRAY 3, 4 OF INTEGER;
    i, j, n: INTEGER;
    tmp: INTEGER;

PROCEDURE PrintArray;
BEGIN
  FOR i := 0 TO LEN(a) - 1 DO
    Out.Int(a[i], 5)
  END;
  Out.Ln
END PrintArray;

BEGIN
  (* fill + bubble sort *)
  FOR i := 0 TO 9 DO a[i] := (i * 37 + 11) MOD 100 END;
  Out.String("before: "); PrintArray;
  FOR i := 0 TO 8 DO
    FOR j := 0 TO 8 - i DO
      IF a[j] > a[j + 1] THEN
        tmp := a[j]; a[j] := a[j + 1]; a[j + 1] := tmp
      END
    END
  END;
  Out.String("sorted: "); PrintArray;

  (* 2D array, row-major *)
  FOR i := 0 TO 2 DO
    FOR j := 0 TO 3 DO
      m[i, j] := i * 10 + j
    END
  END;
  Out.String("m[2,3] = "); Out.Int(m[2, 3], 3); Out.Ln;
  Out.String("LEN(m) = "); Out.Int(LEN(m), 2);
  Out.String(", LEN(m,1) = "); Out.Int(LEN(m, 1), 2); Out.Ln
END Arrays.
