MODULE RealConv;
IMPORT Out;

(* conversion implicite INTEGER -> REAL (ext) *)

VAR r: REAL;
    i: INTEGER;

PROCEDURE Half(x: INTEGER): REAL;   (* RETURN x/2 : division reelle implicite *)
BEGIN
  RETURN x / 2
END Half;

PROCEDURE Show(x: REAL);            (* param REAL recevant un INTEGER *)
BEGIN
  Out.Real(x, 6); Out.Ln
END Show;

BEGIN
  r := 3;                             (* assignation INTEGER -> REAL *)
  Out.String("r="); Out.Real(r, 0); Out.Ln;          (* 3 *)
  Out.String("7/2="); Out.Real(7 / 2, 0); Out.Ln;    (* 3.5 *)
  Out.String("1+2.5="); Out.Real(1 + 2.5, 0); Out.Ln;        (* 3.5 *)
  Out.String("2.5*4="); Out.Real(2.5 * 4, 0); Out.Ln;        (* 10 *)
  Out.String("-3+0.5="); Out.Real(-3 + 0.5, 0); Out.Ln;      (* -2.5 *)
  Out.String("half(7)="); Out.Real(Half(7), 0); Out.Ln;      (* 3.5 *)
  Out.String("show(5):"); Show(5);                            (* 5 *)
  i := 2;
  IF i < 2.5 THEN Out.String("2<2.5=1") ELSE Out.String("2<2.5=0") END; Out.Ln;
  IF 2 = 2.0 THEN Out.String("2=2.0=1") ELSE Out.String("2=2.0=0") END; Out.Ln;
  IF 3.5 >= 3 THEN Out.String("3.5>=3=1") ELSE Out.String("3.5>=3=0") END; Out.Ln;
  Out.String("mix="); Out.Real(i * 1.5 + 1, 0); Out.Ln       (* 4 *)
END RealConv.
