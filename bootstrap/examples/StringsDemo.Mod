MODULE StringsDemo;
IMPORT Out, Strings;

(* exercises lib/Strings (resolved via the lib search path) *)

VAR buf, num: ARRAY 64 OF CHAR;
    n: INTEGER;
    ok: BOOLEAN;

BEGIN
  buf := "Oberon";
  Out.String("len="); Out.Int(Strings.Len(buf), 0); Out.Ln;          (* 6 *)
  Strings.Append(buf, "-07");
  Out.String(buf); Out.Ln;                                            (* Oberon-07 *)
  IF Strings.Equal(buf, "Oberon-07") THEN Out.String("eq=1") ELSE Out.String("eq=0") END; Out.Ln;
  Out.String("cmp="); Out.Int(Strings.Compare(buf, "Oberon-08"), 0); Out.Ln;   (* -1 *)
  Strings.Insert(buf, 6, "!");
  Out.String("ins="); Out.String(buf); Out.Ln;                        (* Oberon!-07 *)
  Strings.IntToStr(-42, num);
  Out.String("i2s="); Out.String(num); Out.Ln;                        (* -42 *)
  ok := Strings.StrToInt(num, n);
  Out.String("s2i="); Out.Int(n, 0);
  IF ok THEN Out.String(" ok=1") ELSE Out.String(" ok=0") END; Out.Ln  (* -42 ok=1 *)
END StringsDemo.
