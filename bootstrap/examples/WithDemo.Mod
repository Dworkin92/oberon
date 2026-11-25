MODULE WithDemo;
IMPORT Out;

(* WITH p: T DO ... END (ext) : p a le type statique POINTER TO T dans le corps,
   avec vérification de type (CHECKTYPE) à l'entrée *)

TYPE
  Shape = RECORD kind: INTEGER END;
  ShapePtr = POINTER TO Shape;
  Circle = RECORD (Shape) radius: REAL END;
  CirclePtr = POINTER TO Circle;
  Rect = RECORD (Shape) w, h: REAL END;
  RectPtr = POINTER TO Rect;

VAR s: ShapePtr;
    c: CirclePtr;
    r: RectPtr;

PROCEDURE Describe(sh: ShapePtr);
BEGIN
  IF sh IS CirclePtr THEN
    WITH sh: Circle DO
      Out.String("circle r="); Out.Real(sh.radius, 0)
    END
  ELSIF sh IS RectPtr THEN
    WITH sh: Rect DO
      Out.String("rect "); Out.Real(sh.w, 0); Out.String("x"); Out.Real(sh.h, 0)
    END
  ELSE
    Out.String("shape kind="); Out.Int(sh.kind, 0)
  END;
  Out.Ln
END Describe;

PROCEDURE Both(a: ShapePtr; b: ShapePtr);
BEGIN
  (* multi-gardes : WITH a: Circle, b: Rect DO ... *)
  WITH a: Circle, b: Rect DO
    Out.String("both: r="); Out.Real(a.radius, 0);
    Out.String(" w="); Out.Real(b.w, 0); Out.Ln
  END
END Both;

BEGIN
  NEW(c); c.kind := 1; c.radius := 2.5;
  NEW(r); r.kind := 2; r.w := 3.0; r.h := 4.0;
  s := c;  Describe(s);
  s := r;  Describe(s);
  NEW(s);  s.kind := 9;  Describe(s);
  Both(c, r);
  (* après le WITH, s a repris son type d'origine *)
  s := c;
  WITH s: Circle DO s.radius := 7.5 END;
  Out.String("after-with kind="); Out.Int(s.kind, 0); Out.Ln;   (* 1, via le type d'origine *)
  Out.String("radius="); Out.Real(s(CirclePtr).radius, 0); Out.Ln (* 7.5 *)
END WithDemo.
