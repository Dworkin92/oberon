MODULE Records;
IMPORT Out;

TYPE
  NodePtr = POINTER TO Node;
  Node = RECORD
    value: INTEGER;
    next: NodePtr
  END;

  Shape = RECORD
    kind: INTEGER
  END;
  ShapePtr = POINTER TO Shape;
  Circle = RECORD (Shape)
    radius: REAL
  END;
  CirclePtr = POINTER TO Circle;

VAR head, p: NodePtr;
    i: INTEGER;
    s: ShapePtr;
    cp: CirclePtr;

PROCEDURE Push(v: INTEGER);
VAR n: NodePtr;
BEGIN
  NEW(n);
  n.value := v;
  n.next := head;
  head := n
END Push;

BEGIN
  head := NIL;
  FOR i := 1 TO 5 DO Push(i * 11) END;
  p := head;
  Out.String("list: ");
  WHILE p # NIL DO
    Out.Int(p.value, 5);
    p := p.next
  END;
  Out.Ln;

  (* type extension + guard + IS *)
  NEW(cp);
  cp.radius := 2.5;
  s := cp;
  IF s IS CirclePtr THEN Out.String("s is a Circle") ELSE Out.String("s is not a Circle") END;
  Out.Ln;
  s(CirclePtr).radius := 3.5;
  Out.String("radius = "); Out.Real(s(CirclePtr).radius, 8); Out.Ln
END Records.
