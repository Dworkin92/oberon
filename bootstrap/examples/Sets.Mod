MODULE Sets;
IMPORT Out;

VAR s: SET;
    vowels: SET;
    i: INTEGER;
    c: CHAR;

PROCEDURE Show(s: SET);
VAR i: INTEGER;
BEGIN
  FOR i := 0 TO 31 DO
    IF i IN s THEN Out.Int(i, 3) END
  END;
  Out.Ln
END Show;

BEGIN
  vowels := {0, 4, 8, 14, 20}; (* A E I O U as letter indexes *)
  s := {1, 2, 3} + {3, 4, 5};
  IF 3 IN s THEN Out.String("3 IN s: yes") ELSE Out.String("3 IN s: no") END;
  Out.Ln;
  IF 9 IN s THEN Out.String("9 IN s: yes") ELSE Out.String("9 IN s: no") END;
  Out.Ln;
  INCL(s, 9);
  EXCL(s, 2);
  Out.String("after INCL(s,9), EXCL(s,2): "); Show(s);
  s := s * {2..9};
  Out.String("s * {2..9}: "); Show(s);
  c := 'e';
  IF ORD(c) - ORD('a') IN vowels THEN
    Out.String("'e' is a vowel"); Out.Ln
  END;
  c := 'x';
  IF ORD(c) - ORD('a') IN vowels THEN
    Out.String("'x' is a vowel"); Out.Ln
  ELSE
    Out.String("'x' is not a vowel"); Out.Ln
  END
END Sets.
