MODULE Nested;
IMPORT Out;

VAR g: INTEGER;

PROCEDURE Outer(x: INTEGER);
  VAR y: INTEGER;

  PROCEDURE Inner(z: INTEGER);
  BEGIN
    (* accesses x, y (outer locals) and g (global): static links *)
    Out.String("Inner: x="); Out.Int(x, 3);
    Out.String(" y="); Out.Int(y, 3);
    Out.String(" z="); Out.Int(z, 3);
    Out.String(" g="); Out.Int(g, 3); Out.Ln;
    y := y + z
  END Inner;

BEGIN
  y := x * 10;
  Inner(1);
  Inner(2);
  Out.String("y after = "); Out.Int(y, 3); Out.Ln
END Outer;

PROCEDURE Swap(VAR a, b: INTEGER);
VAR t: INTEGER;
BEGIN
  t := a; a := b; b := t
END Swap;

VAR a, b: INTEGER;
BEGIN
  g := 99;
  Outer(5);
  a := 1; b := 2;
  Swap(a, b);
  Out.String("a="); Out.Int(a, 2); Out.String(" b="); Out.Int(b, 2); Out.Ln
END Nested.
