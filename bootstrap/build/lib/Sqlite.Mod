MODULE Sqlite;
(* Binding PUR Oberon de SQLite via le FFI generique du module SYSTEM :
     LOADLIB / SYMBOL / CALLC / CSTR / STR / MALLOC / FREE / PEEK.
   Aucune glue C : la DLL sqlite3.dll est chargee a l'execution.
   "sqlite3.dll" d'abord (repertoire de l'exe, PATH), puis le chemin absolu
   C:\Local\Tools\sqlite3\sqlite3.dll en repli.
   Les handles DB et Stmt sont de simples LONGINT (pointeurs sqlite3 et sqlite3_stmt).
   Limitation CALLC : args/retour entiers ou pointeurs (RAX) ; pour une fonction
   C a virgule flottante (ex. sqlite3_column_double -> XMM0), wrapper C mince. *)

IMPORT SYSTEM, Out;



VAR lib, pOpen, pClose, pExec, pPrepare, pStep, pColInt, pColText, pColCount,
    pFinalize, pErrmsg: LONGINT;

PROCEDURE Open*(path: ARRAY OF CHAR; VAR db: LONGINT): INTEGER;
VAR cp, pp, rc: LONGINT;
BEGIN
  cp := SYSTEM.CSTR(path);            (* char* C *)
  pp := SYSTEM.MALLOC(8);             (* sqlite3** out-param *)
  rc := SYSTEM.CALLC(pOpen, 2, cp, pp, 0, 0, 0, 0, 0, 0);
  db := SYSTEM.PEEK(pp);              (* lit le handle alloue par sqlite3_open *)
  SYSTEM.FREE(pp); SYSTEM.FREE(cp);
  RETURN SYSTEM.L2I(rc)
END Open;

PROCEDURE Close*(VAR db: LONGINT);
BEGIN
  IF db # 0 THEN SYSTEM.CALLC(pClose, 1, db, 0, 0, 0, 0, 0, 0, 0); db := 0 END
END Close;

PROCEDURE Exec*(db: LONGINT; sql: ARRAY OF CHAR): INTEGER;
VAR cp, rc: LONGINT;
BEGIN
  cp := SYSTEM.CSTR(sql);
  rc := SYSTEM.CALLC(pExec, 5, db, cp, 0, 0, 0, 0, 0, 0);   (* callback NULL *)
  SYSTEM.FREE(cp);
  RETURN SYSTEM.L2I(rc)
END Exec;

PROCEDURE Prepare*(db: LONGINT; sql: ARRAY OF CHAR; VAR st: LONGINT): INTEGER;
VAR cp, pp, rc: LONGINT;
BEGIN
  cp := SYSTEM.CSTR(sql);
  pp := SYSTEM.MALLOC(8);             (* sqlite3_stmt** out-param *)
  rc := SYSTEM.CALLC(pPrepare, 5, db, cp, -1, pp, 0, 0, 0, 0);  (* nByte = -1 *)
  st := SYSTEM.PEEK(pp);
  SYSTEM.FREE(pp); SYSTEM.FREE(cp);
  RETURN SYSTEM.L2I(rc)
END Prepare;

PROCEDURE Step*(st: LONGINT): INTEGER;   (* 100 = SQLITE_ROW, 101 = SQLITE_DONE *)
BEGIN
  RETURN SYSTEM.L2I(SYSTEM.CALLC(pStep, 1, st, 0, 0, 0, 0, 0, 0, 0))
END Step;

PROCEDURE ColumnInt*(st: LONGINT; i: INTEGER): LONGINT;
BEGIN
  RETURN SYSTEM.CALLC(pColInt, 2, st, i, 0, 0, 0, 0, 0, 0)
END ColumnInt;

PROCEDURE ColumnText*(st: LONGINT; i: INTEGER; VAR buf: ARRAY OF CHAR);
VAR p: LONGINT;
BEGIN
  p := SYSTEM.CALLC(pColText, 2, st, i, 0, 0, 0, 0, 0, 0);  (* const char* *)
  SYSTEM.STR(p, buf)                   (* copie dans le tableau Oberon, tronque a LEN-1 *)
END ColumnText;

PROCEDURE ColumnCount*(st: LONGINT): INTEGER;
BEGIN
  RETURN SYSTEM.L2I(SYSTEM.CALLC(pColCount, 1, st, 0, 0, 0, 0, 0, 0, 0))
END ColumnCount;

PROCEDURE Finalize*(st: LONGINT);
BEGIN
  IF st # 0 THEN SYSTEM.CALLC(pFinalize, 1, st, 0, 0, 0, 0, 0, 0, 0) END
END Finalize;

PROCEDURE Errmsg*(db: LONGINT; VAR buf: ARRAY OF CHAR);
VAR p: LONGINT;
BEGIN
  p := SYSTEM.CALLC(pErrmsg, 1, db, 0, 0, 0, 0, 0, 0, 0);
  SYSTEM.STR(p, buf)
END Errmsg;

BEGIN
  lib := SYSTEM.LOADLIB("sqlite3.dll");
  IF lib = 0 THEN lib := SYSTEM.LOADLIB("C:\\Local\\Tools\\sqlite3\\sqlite3.dll") END;
  IF lib = 0 THEN
    Out.String("Sqlite: sqlite3.dll introuvable (ni PATH ni C:\\Local\\Tools\\sqlite3)"); Out.Ln;
    HALT(2)
  END;
  pOpen := SYSTEM.SYMBOL(lib, "sqlite3_open");
  pClose := SYSTEM.SYMBOL(lib, "sqlite3_close");
  pExec := SYSTEM.SYMBOL(lib, "sqlite3_exec");
  pPrepare := SYSTEM.SYMBOL(lib, "sqlite3_prepare_v2");
  pStep := SYSTEM.SYMBOL(lib, "sqlite3_step");
  pColInt := SYSTEM.SYMBOL(lib, "sqlite3_column_int64");
  pColText := SYSTEM.SYMBOL(lib, "sqlite3_column_text");
  pColCount := SYSTEM.SYMBOL(lib, "sqlite3_column_count");
  pFinalize := SYSTEM.SYMBOL(lib, "sqlite3_finalize");
  pErrmsg := SYSTEM.SYMBOL(lib, "sqlite3_errmsg")
END Sqlite.
