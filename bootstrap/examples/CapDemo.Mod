MODULE CapDemo;
IMPORT Out;

(* CAP prédéfini du rapport Oberon-07 : majuscule d'un CHAR *)

VAR i: INTEGER; s: ARRAY 8 OF CHAR;

BEGIN
  s := "oberon";
  FOR i := 0 TO 5 DO s[i] := CAP(s[i]) END;
  Out.String(s); Out.Ln;                       (* OBERON *)
  Out.Char(CAP('a')); Out.Char(CAP('Z')); Out.Char(CAP('7')); Out.Ln   (* AZ7 *)
END CapDemo.
