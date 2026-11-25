MODULE OpenArr;
IMPORT Out;

(* open arrays: formal params "ARRAY OF T" accept any array of T, any length *)

PROCEDURE Show(s: ARRAY OF CHAR);        (* value open param: accepts literals too *)
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < LEN(s, 0)) & (s[i] # 0X) DO Out.Char(s[i]); INC(i) END
END Show;

PROCEDURE Print(VAR s: ARRAY OF CHAR);    (* VAR open param *)
BEGIN Show(s) END Print;                 (* forwarding an open param *)

PROCEDURE Sum(a: ARRAY OF INTEGER): INTEGER;
VAR i, t: INTEGER;
BEGIN t := 0; FOR i := 0 TO LEN(a, 0)-1 DO t := t + a[i] END; RETURN t
END Sum;

PROCEDURE Fill(VAR a: ARRAY OF INTEGER; v: INTEGER);  (* write through open VAR *)
VAR i: INTEGER;
BEGIN FOR i := 0 TO LEN(a, 0)-1 DO a[i] := v * i END
END Fill;

VAR buf: ARRAY 32 OF CHAR;
    nums: ARRAY 5 OF INTEGER;
    big: ARRAY 100 OF INTEGER;
    i: INTEGER;

BEGIN
  buf := "hello open arrays";
  Print(buf); Out.Ln;
  Show("a literal!"); Out.Ln;

  FOR i := 0 TO 4 DO nums[i] := i + 1 END;
  Out.String("sum5="); Out.Int(Sum(nums), 0); Out.Ln;          (* 15 *)
  Fill(nums, 10);
  Out.String("sum5after="); Out.Int(Sum(nums), 0); Out.Ln;     (* 0+10+20+30+40 = 100 *)

  Fill(big, 1);
  Out.String("len100="); Out.Int(LEN(big, 0), 0);
  Out.String(" sum100="); Out.Int(Sum(big), 0); Out.Ln         (* 4950 *)
END OpenArr.
