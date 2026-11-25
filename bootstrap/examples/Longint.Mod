MODULE Longint;
IMPORT Out;

VAR big: LONGINT;
    i: INTEGER;
    l: LONGINT;

BEGIN
  (* literal too big for INTEGER becomes LONGINT automatically *)
  big := 10000000000;
  Out.String("big = "); Out.Long(big, 15); Out.Ln;

  big := big * 1000 + 7;
  Out.String("big*1000+7 = "); Out.Long(big, 20); Out.Ln;

  (* mixing INTEGER and LONGINT promotes to LONGINT *)
  i := 5;
  Out.String("big + i = "); Out.Long(big + i, 20); Out.Ln;

  IF big > 9999999999 THEN Out.String("big > 2^32-ish: yes"); Out.Ln END;

  (* INT64 min via arithmetic *)
  l := -9223372036854775807 - 1;
  Out.String("int64 min = "); Out.Long(l, 21); Out.Ln;

  Out.String("ABS(min+1) = "); Out.Long(ABS(l + 1), 21); Out.Ln;
  IF ODD(l) THEN Out.String("min is odd"); Out.Ln END;
  Out.String("l DIV 3 = "); Out.Long(l DIV 3, 21);
  Out.String(", l MOD 3 = "); Out.Long(l MOD 3, 3); Out.Ln;

  (* INTEGER var widens to LONGINT on assignment *)
  l := i;
  Out.String("l := i -> "); Out.Long(l, 5); Out.Ln;

  (* LONGINT FOR loop *)
  FOR l := 9000000000000 TO 9000000000002 DO Out.Long(l, 15) END;
  Out.Ln
END Longint.
