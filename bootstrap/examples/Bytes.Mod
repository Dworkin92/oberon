MODULE Bytes;
IMPORT Out, In;

(* reads raw bytes from stdin, prints them as decimal numbers *)
VAR b: INTEGER;

BEGIN
  REPEAT
    In.Byte(b);
    IF b >= 0 THEN Out.Int(b, 4) END
  UNTIL b < 0;
  Out.Ln
END Bytes.
