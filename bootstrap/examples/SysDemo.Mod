MODULE SysDemo;
IMPORT Out, SYSTEM;

VAR buf: ARRAY 256 OF CHAR;
    i: INTEGER;
    r: REAL;

BEGIN
  (* program arguments: obvm SysDemo.obc alpha 42 -> ARGC = 2 *)
  Out.String("ARGC="); Out.Int(SYSTEM.ARGC, 0); Out.Ln;
  i := 0;
  WHILE i < SYSTEM.ARGC DO
    SYSTEM.ARGV(i, buf);
    Out.String("arg"); Out.Int(i, 0); Out.String("=["); Out.String(buf); Out.String("]"); Out.Ln;
    INC(i)
  END;

  (* bitwise ops on LONGINT (INTEGER args widen automatically) *)
  Out.String("BAND="); Out.Long(SYSTEM.BAND(255, 15), 0); Out.Ln;
  Out.String("BOR="); Out.Long(SYSTEM.BOR(240, 15), 0); Out.Ln;
  Out.String("BXOR="); Out.Long(SYSTEM.BXOR(255, 85), 0); Out.Ln;
  Out.String("BNOT="); Out.Long(SYSTEM.BNOT(255), 0); Out.Ln;
  Out.String("LSH4="); Out.Long(SYSTEM.LSH(255, 4), 0); Out.Ln;
  Out.String("LSHm4="); Out.Long(SYSTEM.LSH(255, -4), 0); Out.Ln;
  Out.String("ROT63="); Out.Long(SYSTEM.ROT(1, 63), 0); Out.Ln;
  IF SYSTEM.BIT(255, 8) THEN Out.String("BIT8=1") ELSE Out.String("BIT8=0") END; Out.Ln;
  IF SYSTEM.BIT(255, 4) THEN Out.String("BIT4=1") ELSE Out.String("BIT4=0") END; Out.Ln;

  (* 64-bit literal (too big for INTEGER) *)
  Out.String("BAND64="); Out.Long(SYSTEM.BAND(123456789012345, 4294967295), 0); Out.Ln;

  (* casts (needed by the Oberon-written VM) *)
  Out.String("L2I="); Out.Int(SYSTEM.L2I(4294967297), 0); Out.Ln;       (* 4294967297 -> 1 *)
  r := SYSTEM.BITSREAL(4607182418800017408);                            (* bits de 1.0 *)
  Out.String("BITSREAL="); Out.Real(r, 0); Out.Ln;                      (* 1 *)
  Out.String("REALBITS="); Out.Long(SYSTEM.REALBITS(2.5), 0); Out.Ln;   (* 4612811918334230528 *)
  Out.String("I2REAL="); Out.Real(SYSTEM.I2REAL(3), 0); Out.Ln;          (* 3 *)

  (* clock: just check it is non-negative *)
  IF SYSTEM.TICKS() >= 0 THEN Out.String("TICKS ok"); Out.Ln END
END SysDemo.
