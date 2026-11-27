MODULE SqlDemo;
IMPORT Out, Sqlite;

(* SQLite via lib/Sqlite.Mod : binding PUR Oberon au-dessus du FFI SYSTEM
   (LOADLIB sqlite3.dll + SYMBOL + CALLC).  Base en memoire, aucun fichier. *)

VAR db, st: LONGINT;
    rc, n: INTEGER;
    name: ARRAY 32 OF CHAR;

BEGIN
  rc := Sqlite.Open(":memory:", db);
  Out.String("open rc="); Out.Int(rc, 0); Out.Ln;
  rc := Sqlite.Exec(db, "CREATE TABLE t(name TEXT, val INTEGER); INSERT INTO t VALUES ('alice', 42), ('bob', 7);");
  Out.String("exec rc="); Out.Int(rc, 0); Out.Ln;
  rc := Sqlite.Prepare(db, "SELECT name, val FROM t ORDER BY val;", st);
  Out.String("prep rc="); Out.Int(rc, 0);
  n := Sqlite.ColumnCount(st);
  Out.String(" cols="); Out.Int(n, 0); Out.Ln;
  WHILE Sqlite.Step(st) = 100 DO
    Sqlite.ColumnText(st, 0, name);
    Out.String(name); Out.String(" -> ");
    Out.Long(Sqlite.ColumnInt(st, 1), 0); Out.Ln
  END;
  Sqlite.Finalize(st);
  rc := Sqlite.Exec(db, "INSERT INTO nope VALUES (1);");   (* erreur volontaire *)
  Out.String("bad rc="); Out.Int(rc, 0); Out.String(" msg=");
  Sqlite.Errmsg(db, name);
  Out.String(name); Out.Ln;
  Sqlite.Close(db)
END SqlDemo.
