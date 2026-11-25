MODULE Sem;
IMPORT Out;
VAR s: ARRAY 32 OF CHAR;
BEGIN
  Out.Int(-7 DIV 2, 4); Out.Int(-7 MOD 2, 4); Out.Ln;
  Out.Int(7 DIV (-2), 4); Out.Int(7 MOD (-2), 4); Out.Ln;
  Out.Int(ENTIER(3.99), 3); Out.Int(ENTIER(-3.99), 4); Out.Ln;
  Out.Int(FLOOR(3.99), 3); Out.Int(FLOOR(-3.99), 4); Out.Ln;
  Out.Int(ABS(-5), 3); Out.Real(ABS(-2.5), 6); Out.Ln;
  IF ODD(7) THEN Out.String("7 odd") ELSE Out.String("7 even") END; Out.Ln;
  s := "abc";
  Out.String(s); Out.String(" len="); Out.Int(LEN(s), 0); Out.Ln;
  COPY("xy", s);
  Out.String(s); Out.Ln;
  Out.Real(1.5 / 4.0, 10); Out.Ln;
  HALT(3)
END Sem.
