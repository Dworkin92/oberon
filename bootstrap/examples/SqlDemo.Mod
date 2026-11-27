MODULE SqlDemo;
IMPORT Out, SQLite;

(* builtin module SQLite (vendored amalgamation, static link) :
   DB / Stmt = LONGINT handles.  In-memory database, no file, no callback. *)

VAR db: SQLite.DB; st: SQLite.Stmt;
    rc, n, i: INTEGER;
    name: ARRAY 32 OF CHAR;

BEGIN
  rc := SQLite.Open(":memory:", db);
  Out.String("open rc="); Out.Int(rc, 0); Out.Ln;
  rc := SQLite.Exec(db, "CREATE TABLE t(name TEXT, val INTEGER); INSERT INTO t VALUES ('alice', 42), ('bob', 7);");
  Out.String("exec rc="); Out.Int(rc, 0); Out.Ln;
  rc := SQLite.Prepare(db, "SELECT name, val FROM t ORDER BY val;", st);
  Out.String("prep rc="); Out.Int(rc, 0);
  n := SQLite.ColumnCount(st);
  Out.String(" cols="); Out.Int(n, 0); Out.Ln;
  WHILE SQLite.Step(st) = 100 DO
    SQLite.ColumnText(st, 0, name);
    Out.String(name); Out.String(" -> ");
    Out.Long(SQLite.ColumnInt(st, 1), 0); Out.Ln
  END;
  SQLite.Finalize(st);
  rc := SQLite.Exec(db, "INSERT INTO nope VALUES (1);");   (* syntax error on purpose *)
  Out.String("bad rc="); Out.Int(rc, 0); Out.String(" msg=");
  SQLite.Errmsg(db, name);
  Out.String(name); Out.Ln;
  SQLite.Close(db)
END SqlDemo.
