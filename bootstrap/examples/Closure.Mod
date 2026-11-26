MODULE Closure;
IMPORT Out;

TYPE Maker = PROCEDURE (x: INTEGER): INTEGER;

PROCEDURE MakeAdder(n: INTEGER): Maker;
  PROCEDURE AddN(x: INTEGER): INTEGER;
  BEGIN RETURN x + n
  END AddN;
BEGIN RETURN AddN
END MakeAdder;

PROCEDURE MakeCounter(): Maker;
VAR c: INTEGER;
  PROCEDURE Next(x: INTEGER): INTEGER;
  BEGIN c := c + 1; RETURN c * 100 + x
  END Next;
BEGIN c := 0; RETURN Next
END MakeCounter;

VAR add5, add10, cnt: Maker;

BEGIN
  add5 := MakeAdder(5);
  add10 := MakeAdder(10);
  Out.Int(add5(1), 0); Out.Ln;    (* 6 *)
  Out.Int(add10(1), 0); Out.Ln;   (* 11 *)
  Out.Int(add5(2), 0); Out.Ln;    (* 7 : n capture = 5, independent de add10 *)
  cnt := MakeCounter();
  Out.Int(cnt(0), 0); Out.Ln;     (* 100 *)
  Out.Int(cnt(0), 0); Out.Ln;     (* 200 : etat capture persistant *)
  Out.Int(cnt(7), 0); Out.Ln      (* 307 *)
END Closure.
