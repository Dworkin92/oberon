/* sqlite_glue.c - builtin module SQLite for the Oberon-07 VM.
 *
 * SQLite is vendored as the official amalgamation (bootstrap/ext/sqlite/sqlite3.[ch],
 * compiled to ext/sqlite/sqlite3.o and linked statically into obvm.exe and into
 * the native binaries produced by ob2c + gcc).  We deliberately do NOT use
 * C:\Windows\System32\winsqlite3.dll, so the produced executables are
 * self-contained.
 *
 * Oberon-side API (module SQLite, builtin ids 60..70, see parser.c):
 *   TYPE DB = LONGINT; Stmt = LONGINT;   (* sqlite3* / sqlite3_stmt* handles *)
 *   Open(path: ARRAY OF CHAR; VAR db: DB): INTEGER
 *   Close(VAR db: DB)
 *   Exec(db: DB; sql: ARRAY OF CHAR): INTEGER
 *   Prepare(db: DB; sql: ARRAY OF CHAR; VAR st: Stmt): INTEGER
 *   Step(st: Stmt): INTEGER               (* 100 = SQLITE_ROW, 101 = DONE *)
 *   ColumnInt(st: Stmt; i: INTEGER): LONGINT
 *   ColumnText(st: Stmt; i: INTEGER; VAR buf: ARRAY OF CHAR)
 *   ColumnDouble(st: Stmt; i: INTEGER): REAL
 *   ColumnCount(st: Stmt): INTEGER
 *   Finalize(st: Stmt)
 *   Errmsg(db: DB; VAR buf: ARRAY OF CHAR)
 *
 * No C->Oberon callbacks are used (sqlite3_exec with NULL callback; the
 * prepare/step/column loop instead), so the VM never needs to be re-entered.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "rt.h"
#include "../ext/sqlite/sqlite3.h"

/* cell-array (one char per 8-byte cell) -> C string */
static void refToCStr(VM *vm, Cell ref, char *buf, int max) {
  int n = 0;
  if (ref) {
    int ndim = (int)-vm->heap[ref];
    int total = (int)vm->heap[ref + ndim + 1];
    int hdr = ndim + 2;
    for (int i = 0; i < total && n < max - 1; i++) {
      Cell c = vm->heap[ref + hdr + i];
      if (c == 0) break;
      buf[n++] = (char)c;
    }
  }
  buf[n] = 0;
}

/* C string -> cell-array; slotAddr is the address of the array variable's slot */
static void cStrToRef(VM *vm, Cell slotAddr, const char *s) {
  Cell ref = memRead(vm, slotAddr);
  if (!ref) return;
  int ndim = (int)-vm->heap[ref];
  int total = (int)vm->heap[ref + ndim + 1];
  int hdr = ndim + 2;
  int n = s ? (int)strlen(s) : 0;
  if (n > total - 1) n = total - 1;
  for (int i = 0; i < n; i++) vm->heap[ref + hdr + i] = (unsigned char)s[i];
  vm->heap[ref + hdr + n] = 0;
}

/* returns 1 if id was handled */
int sqliteBuiltin(VM *vm, int id, Cell *arg, int base) {
  char nm[1024], sql[8192];
  sqlite3 *db;
  sqlite3_stmt *st;
  switch (id) {
    case 60: /* Open(path, VAR db): INTEGER */
      refToCStr(vm, arg[0], nm, sizeof nm);
      db = 0;
      vm->stack[base] = sqlite3_open(nm, &db);
      memWrite(vm, arg[1], (Cell)(intptr_t)db);
      return 1;
    case 61: /* Close(VAR db) */
      db = (sqlite3 *)(intptr_t)memRead(vm, arg[0]);
      if (db) sqlite3_close(db);
      memWrite(vm, arg[0], 0);
      return 1;
    case 62: /* Exec(db, sql): INTEGER */
      refToCStr(vm, arg[1], sql, sizeof sql);
      db = (sqlite3 *)(intptr_t)arg[0];
      vm->stack[base] = db ? sqlite3_exec(db, sql, 0, 0, 0) : -1;
      return 1;
    case 63: /* Prepare(db, sql, VAR st): INTEGER */
      refToCStr(vm, arg[1], sql, sizeof sql);
      db = (sqlite3 *)(intptr_t)arg[0];
      st = 0;
      vm->stack[base] = db ? sqlite3_prepare_v2(db, sql, -1, &st, 0) : -1;
      memWrite(vm, arg[2], (Cell)(intptr_t)st);
      return 1;
    case 64: /* Step(st): INTEGER */
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      vm->stack[base] = st ? sqlite3_step(st) : -1;
      return 1;
    case 65: /* ColumnInt(st, i): LONGINT */
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      vm->stack[base] = st ? (Cell)sqlite3_column_int64(st, (int)arg[1]) : 0;
      return 1;
    case 66: { /* ColumnText(st, i, VAR buf) */
      const unsigned char *t;
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      t = st ? sqlite3_column_text(st, (int)arg[1]) : 0;
      cStrToRef(vm, arg[2], t ? (const char *)t : "");
      return 1;
    }
    case 67: /* ColumnDouble(st, i): REAL */
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      vm->stack[base] = cellFromDouble(st ? sqlite3_column_double(st, (int)arg[1]) : 0.0);
      return 1;
    case 68: /* ColumnCount(st): INTEGER */
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      vm->stack[base] = st ? sqlite3_column_count(st) : 0;
      return 1;
    case 69: /* Finalize(st) */
      st = (sqlite3_stmt *)(intptr_t)arg[0];
      if (st) sqlite3_finalize(st);
      return 1;
    case 70: /* Errmsg(db, VAR buf) */
      db = (sqlite3 *)(intptr_t)arg[0];
      cStrToRef(vm, arg[1], db ? sqlite3_errmsg(db) : "");
      return 1;
  }
  return 0;
}
