MODULE CaseLabels;
IMPORT Out;

(* regression: multi-label CASE branches (a, b, c:) must match any label,
   and a dense CASE (>= 8 labels) must take the OP_JUMPTABLE path *)

VAR x, sum: INTEGER;

BEGIN
  FOR x := -1 TO 4 DO
    CASE x OF
      -1, 0: Out.String("a")
    | 1, 2, 3: Out.String("b")
    | 4..9: Out.String("c")
    ELSE Out.String("e")
    END
  END;
  Out.Ln;

  (* dense CASE 0..9 -> OP_JUMPTABLE; x = 10..12 -> ELSE *)
  sum := 0;
  FOR x := 0 TO 12 DO
    CASE x OF
      0: sum := sum + 1
    | 1: sum := sum + 2
    | 2: sum := sum + 3
    | 3: sum := sum + 4
    | 4: sum := sum + 5
    | 5: sum := sum + 6
    | 6: sum := sum + 7
    | 7: sum := sum + 8
    | 8: sum := sum + 9
    | 9: sum := sum + 10
    ELSE sum := sum + 100
    END
  END;
  Out.String("sum="); Out.Int(sum, 0); Out.Ln   (* 55 + 300 = 355 *)
END CaseLabels.
