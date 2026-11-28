MODULE LexDump;
IMPORT Out, SYSTEM, OCS;

(* Test du scanner Oberon (selfhost/OCS.Mod) : dump des tokens du fichier passé
   en argument (argv 0), un par ligne : nom [valeur]. *)

VAR path: ARRAY 256 OF CHAR; sn: ARRAY 32 OF CHAR;

BEGIN
  IF SYSTEM.ARGC < 1 THEN Out.String("usage: LexDump <file.Mod>"); Out.Ln; HALT(2) END;
  SYSTEM.ARGV(0, path);
  OCS.Open(path);
  WHILE OCS.sym # OCS.S_EOF DO
    OCS.SymName(OCS.sym, sn);
    Out.String(sn);
    IF OCS.sym = OCS.S_IDENT THEN Out.Char(' '); Out.String(OCS.name)
    ELSIF OCS.sym = OCS.S_INT THEN Out.Char(' '); Out.Long(OCS.ival, 0)
    ELSIF OCS.sym = OCS.S_REAL THEN Out.Char(' '); Out.Real(OCS.rval, 0)
    ELSIF OCS.sym = OCS.S_CHAR THEN Out.Char(' '); Out.Int(OCS.cval, 0)
    ELSIF OCS.sym = OCS.S_STRING THEN Out.Char(' '); Out.Char('"'); Out.String(OCS.sval); Out.Char('"')
    END;
    Out.Ln;
    OCS.Next
  END
END LexDump.
