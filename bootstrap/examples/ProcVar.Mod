MODULE ProcVar;
IMPORT Out;

TYPE
  BinOp = PROCEDURE (x, y: INTEGER): INTEGER;
  Pred = PROCEDURE (x: INTEGER): BOOLEAN;

PROCEDURE Add(x, y: INTEGER): INTEGER;
BEGIN RETURN x + y
END Add;

PROCEDURE Mul(x, y: INTEGER): INTEGER;
BEGIN RETURN x * y
END Mul;

PROCEDURE Sub(x, y: INTEGER): INTEGER;
BEGIN RETURN x - y
END Sub;

PROCEDURE IsPos(x: INTEGER): BOOLEAN;
BEGIN RETURN x > 0
END IsPos;

PROCEDURE IsEven(x: INTEGER): BOOLEAN;
BEGIN RETURN x MOD 2 = 0
END IsEven;

PROCEDURE Apply(op: BinOp; a, b: INTEGER): INTEGER;
BEGIN RETURN op(a, b)
END Apply;

VAR f, g: BinOp; p: Pred;

BEGIN
  f := Add;
  Out.Int(f(3, 4), 0); Out.Ln;            (* 7 *)
  f := Mul;
  Out.Int(f(3, 4), 0); Out.Ln;            (* 12 *)
  g := Sub; f := g;                       (* copy proc var to proc var *)
  Out.Int(Apply(f, 10, 3), 0); Out.Ln;    (* 7 *)
  Out.Int(Apply(Add, 2, 5), 0); Out.Ln;   (* 7 : proc ident as argument *)
  p := IsPos;
  IF p(5) THEN Out.String("pos") END; Out.Ln;
  p := IsEven;
  IF p(4) THEN Out.String("even") END; Out.Ln;
  f := NIL;
  IF f = NIL THEN Out.String("nil") END; Out.Ln
END ProcVar.
