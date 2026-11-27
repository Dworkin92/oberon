MODULE TypeCase;
IMPORT Out;

(* CASE de type Oberon-07 (remplace WITH, retiré du langage) :
   CASE p OF T1: S1 | T2: S2 ELSE S3 END avec p : POINTER TO RECORD.
   Dans une branche, p a statiquement le type du label (narrowing),
   avec vérification runtime (ISTYPE sur la chaîne d'extension + CHECKTYPE). *)

TYPE
  Shape = POINTER TO ShapeDesc;
  ShapeDesc = RECORD END;
  Circle = POINTER TO CircleDesc;
  CircleDesc = RECORD (ShapeDesc) r: INTEGER END;
  Rect = POINTER TO RectDesc;
  RectDesc = RECORD (ShapeDesc) w, h: INTEGER END;

VAR s: Shape; c: Circle; r: Rect;

PROCEDURE Describe(sh: Shape);
BEGIN
  CASE sh OF
    Circle: Out.String("circle r="); Out.Int(sh.r, 0); Out.Ln
  | Rect: Out.String("rect "); Out.Int(sh.w, 0); Out.String("x"); Out.Int(sh.h, 0); Out.Ln
  ELSE Out.String("shape"); Out.Ln
  END
END Describe;

BEGIN
  NEW(c); c.r := 3; Describe(c);
  NEW(r); r.w := 4; r.h := 5; Describe(r);
  NEW(s); Describe(s)
END TypeCase.
