MODULE FilesDemo;
IMPORT Out, Files;

PROCEDURE B(b: BOOLEAN): INTEGER;
BEGIN IF b THEN RETURN 1 ELSE RETURN 0 END
END B;

VAR f: Files.File;
    i, b, sum: INTEGER;
    buf: ARRAY 16 OF CHAR;

BEGIN
  (* write a binary file: bytes 0..255 then "hello" *)
  f := Files.Create("tests/out/demo.bin");
  IF f = NIL THEN Out.String("create failed"); Out.Ln; HALT(1) END;
  FOR i := 0 TO 255 DO Files.WriteByte(f, i) END;
  Files.Write(f, "hello", 5);
  Files.Close(f);

  (* read it back *)
  Out.String("exists: "); Out.Int(B(Files.Exists("tests/out/demo.bin")), 1); Out.Ln;
  f := Files.Open("tests/out/demo.bin");
  IF f = NIL THEN Out.String("open failed"); Out.Ln; HALT(1) END;
  Out.String("length: "); Out.Long(Files.Length(f), 5); Out.Ln;
  sum := 0;
  REPEAT
    b := Files.ReadByte(f);
    IF b >= 0 THEN sum := sum + b END
  UNTIL b < 0;
  Out.String("sum of all bytes: "); Out.Int(sum, 6); Out.Ln;
  Out.String("eof: "); Out.Int(B(Files.Eof(f)), 1); Out.Ln;

  (* seek to 256 and read the 5 text bytes with Read *)
  Files.Set(f, 256);
  Out.String("pos: "); Out.Long(Files.Pos(f), 5); Out.Ln;
  i := Files.Read(f, buf, 5);
  Out.String("read "); Out.Int(i, 2); Out.String(" bytes: ");
  FOR i := 0 TO 4 DO Out.Char(buf[i]) END;
  Out.Ln;
  Files.Close(f);

  Files.Delete("tests/out/demo.bin");
  Out.String("after delete, exists: "); Out.Int(B(Files.Exists("tests/out/demo.bin")), 1); Out.Ln
END FilesDemo.
