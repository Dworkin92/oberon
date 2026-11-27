MODULE RecVar;
IMPORT Out;

TYPE
  Point = RECORD x, y: INTEGER END;
  Line = RECORD a, b: Point END;  (* nested record field *)

PROCEDURE Move(VAR p: Point; dx, dy: INTEGER);
BEGIN p.x := p.x + dx; p.y := p.y + dy
END Move;

VAR pt, q: Point; ln: Line; arr: ARRAY 3 OF Point; p: POINTER TO Point; pa: POINTER TO ARRAY 2 OF Point;

BEGIN
  pt.x := 1; pt.y := 2;
  Move(pt, 10, 20);                                            (* VAR record param on inline var *)
  q := pt;                                                     (* record assignment *)
  Move(q, 1, 1);
  Out.Int(pt.x, 0); Out.String(","); Out.Int(pt.y, 0); Out.String("  ");
  Out.Int(q.x, 0); Out.String(","); Out.Int(q.y, 0); Out.Ln;     (* 11,22  12,23 *)
  ln.a := pt; ln.b := q;                                       (* nested record fields *)
  Out.Int(ln.a.x + ln.b.x, 0); Out.Ln;                         (* 23 *)
  arr[0] := pt; arr[1] := q;
  Move(arr[1], 100, 0);                                        (* VAR param on array element *)
  Out.Int(arr[0].x, 0); Out.String(","); Out.Int(arr[1].x, 0); Out.Ln;  (* 11,112 *)
  NEW(p); p^ := arr[0]; Move(p^, 5, 5);                        (* VAR param through p^ *)
  Out.Int(p^.x, 0); Out.String(","); Out.Int(p^.y, 0); Out.Ln;  (* 16,27 *)
  NEW(pa); pa^[0].x := 7; pa^[1] := p^; DISPOSE(pa);           (* NEW/DISPOSE on POINTER TO ARRAY OF record *)
  Out.Int(arr[1].y, 0); Out.Ln                                 (* 23 : heap not corrupted *)
END RecVar.
