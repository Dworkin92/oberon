MODULE DynArr;
IMPORT Out;

(* NEW / DISPOSE sur POINTER TO ARRAY + free-list *)

TYPE Buf = ARRAY 8 OF INTEGER;

VAR p, q: POINTER TO ARRAY 8 OF INTEGER;
    r: POINTER TO Buf;
    i, s: INTEGER;

PROCEDURE Sum(VAR a: ARRAY OF INTEGER): INTEGER;
VAR i, s: INTEGER;
BEGIN
  s := 0;
  FOR i := 0 TO LEN(a, 0)-1 DO s := s + a[i] END;
  RETURN s
END Sum;

BEGIN
  NEW(p);
  Out.String("len="); Out.Int(LEN(p, 0), 0); Out.Ln;          (* 8 *)
  FOR i := 0 TO 7 DO p[i] := i * i END;
  Out.String("sum="); Out.Int(Sum(p), 0); Out.Ln;              (* 140, p passe en VAR open *)
  DISPOSE(p);
  IF p = NIL THEN Out.String("nil=1") ELSE Out.String("nil=0") END; Out.Ln;
  NEW(p);                                                          (* reutilise le bloc libere *)
  FOR i := 0 TO 7 DO p[i] := 0 END;
  p[3] := 42;
  Out.String("reuse="); Out.Int(p[3], 0); Out.Ln;              (* 42 *)
  NEW(q);
  FOR i := 0 TO 7 DO q[i] := 100 + i END;
  Out.String("qsum="); Out.Int(Sum(q), 0); Out.Ln;             (* 828 *)
  DISPOSE(q);
  NEW(r);                                                          (* via type nomme *)
  FOR i := 0 TO 7 DO r[i] := 1 END;
  Out.String("rsum="); Out.Int(Sum(r), 0); Out.Ln;              (* 8 *)
  DISPOSE(r);
  DISPOSE(p);
  DISPOSE(p);                                                      (* double DISPOSE -> erreur runtime attendue? non: NIL est ok *)
  Out.String("done"); Out.Ln
END DynArr.
