/* parser.c - single-pass Oberon-07 compiler: lexer -> semantics -> bytecode */
#include "ob.h"
#include "lexer.h"
#include "model.h"
#include "module.h"
#include "parser.h"

/* predefined procedure ids (Obj with modId == -1) */
enum { PD_ABS = 1, PD_ODD, PD_LEN, PD_ORD, PD_CHR, PD_ENTIER, PD_FLOOR,
       PD_NEW = 20, PD_INC, PD_DEC, PD_INCL, PD_EXCL, PD_COPY, PD_HALT, PD_DISPOSE,
       PD_PROCV, PD_PROCC, PD_CAP };

/* builtin module proc ids (module id 255) */
enum { B_OUT_INT = 0, B_OUT_REAL, B_OUT_CHAR, B_OUT_STRING, B_OUT_LN,
       B_IN_INT = 5, B_IN_REAL, B_IN_CHAR, B_IN_LINE,
       B_HALT = 9, B_OUT_LONG = 10, B_OUT_BYTE = 11, B_IN_BYTE = 12,
       B_FILES_OPEN = 20, B_FILES_CREATE, B_FILES_CLOSE, B_FILES_READBYTE,
       B_FILES_WRITEBYTE, B_FILES_READ, B_FILES_WRITE, B_FILES_EOF,
       B_FILES_LENGTH, B_FILES_POS, B_FILES_SET, B_FILES_DELETE, B_FILES_EXISTS,
       B_SYS_BAND = 40, B_SYS_BOR, B_SYS_BXOR, B_SYS_BNOT,
       B_SYS_LSH, B_SYS_ROT, B_SYS_BIT, B_SYS_ARGC, B_SYS_ARGV,
       B_SYS_TICKS, B_SYS_EXIT,
       B_SYS_L2I = 51, B_SYS_REALBITS, B_SYS_BITSREAL, B_SYS_I2REAL,
       /* FFI generique (src/ffi_glue.c) : 60..70 reserves (ancien builtin SQLite,
          remplacé par lib/Sqlite.Mod au-dessus du FFI) */
       B_FFI_CALLC = 80, B_FFI_LOADLIB, B_FFI_SYMBOL, B_FFI_FREELIB,
       B_FFI_CSTR, B_FFI_STR, B_FFI_MALLOC, B_FFI_FREE, B_FFI_PEEK, B_FFI_POKE,
       B_FFI_GETENV = 90, B_FFI_EXEPATH };

#define M_VAL 0
#define M_ADDR 1
#define M_VARARG 2

static int curLevel;
static Obj *builtinOut, *builtinIn, *builtinFiles, *builtinSystem;
static Obj *withShadows[64]; static int nWithShadows; /* WITH guards: vars shadowed in current scope */

static int isIntLike(Type *t) { return t == typeInt || t == typeLongint; }

/* ---------- emission helpers ---------- */
static void emit(int op) { bufU8(&curProc->code, op); }
/* implicit INTEGER -> REAL conversion (ext): stack holds [a, b]; convert the top (b) */
static void emitI2FTop(Type *t) { if (t == typeInt) emit(OP_I2F); }
/* convert the value UNDER the top (a): SWAP, I2F, SWAP */
static void emitI2FBelow(Type *t) { if (t == typeInt) { emit(OP_SWAP); emit(OP_I2F); emit(OP_SWAP); } }
static void emit32(int op, uint32_t v) { emit(op); bufU32(&curProc->code, v); }
static int here(void) { return curProc->code.len; }
static void patch32(int pos, uint32_t v) {
  Buf *b = &curProc->code;
  b->b[pos] = (unsigned char)v; b->b[pos + 1] = (unsigned char)(v >> 8);
  b->b[pos + 2] = (unsigned char)(v >> 16); b->b[pos + 3] = (unsigned char)(v >> 24);
}
static void emitGlobalOp(int op, int mod, int off) {
  emit(op); bufU8(&curProc->code, mod); bufU32(&curProc->code, (uint32_t)off);
}
static void emitTypeOp(int op, int mod, int idx) {
  emit(op); bufU8(&curProc->code, mod); bufU32(&curProc->code, (uint32_t)idx);
}
static int emitJump(int op) { emit(op); int pos = here(); bufU32(&curProc->code, 0); return pos; } /* returns pos of operand */
static int allocTemp(void) { return curProc->nlocals++; }

static void expect(int s) {
  if (sym != s) obError(line, "syntax error: expected %s, got %s", symName(s), symName(sym));
  nextSym();
}
static int accept(int s) { if (sym == s) { nextSym(); return 1; } return 0; }
/* consume an identifier, copying its text first (expect() would clobber `name`) */
static void readIdent(char *buf) {
  if (sym != S_IDENT) obError(line, "syntax error: expected identifier, got %s", symName(sym));
  memcpy(buf, name, 64); buf[63] = 0;
  nextSym();
}

/* ---------- imports cache ---------- */
typedef struct { char name[64]; LoadedModule *lm; int modId; } ImpEnt;
static ImpEnt impCache[64];
static int nImpCache;

static int fileExists(const char *p) { FILE *f = fopen(p, "rb"); if (f) { fclose(f); return 1; } return 0; }

/* find (module, typeidx) where type t is defined */
static void findTypeRef(Type *t, int *mod, int *idx) {
  for (int i = 0; i < curMod->ntypes; i++)
    if (curMod->types[i].t == t) { *mod = 0; *idx = i; return; }
  for (int i = 0; i < nImpCache; i++) {
    LoadedModule *lm = impCache[i].lm;
    for (int j = 0; j < lm->ntypes; j++)
      if (lm->types[j] == t) { *mod = impCache[i].modId; *idx = j; return; }
  }
  registerTypeDeep(curMod, t); /* deep: nested types (array of array, record fields...) must be registered too */
  *mod = 0; *idx = typeIndex(curMod, t);
}

/* ---------- forward decls ---------- */
static Type *parseExpression(void);
static Type *parseSimpleExpr(void);
static Type *parseTerm(void);
static Type *parseFactor(void);
static void parseStatements(void);
static void parseStatement(void);
static int isEndSym(void);
static Type *parseDesignator(int mode, Obj *o, int mod);
static Obj *readFirstIdent(int *mod);
static Type *parseType(void);
static Type *parseQualType(void);
static Cell parseConstExpr(Type **t);
static void parseCallArgs(Obj *proc, int mod);
static void parseArgsList(Obj *params, const char *nm);
static void emitCall(Obj *proc, int mod);

/* ---------- predefined & builtins ---------- */
static Obj *mkPredefProc(const char *nm, int id, int nparams, int *varFlags, Type **ptypes) {
  Obj *o = newObj(nm, CL_PROC);
  o->modId = -1;
  o->builtinId = id;
  o->nparams = nparams;
  o->params = NULL;
  Obj **tail = &o->params;
  for (int i = 0; i < nparams; i++) {
    Obj *p = newObj("", CL_VAR);
    p->type = ptypes[i];
    p->isVarParam = varFlags[i];
    *tail = p; tail = &p->nextParam;
  }
  return o;
}

static void installPredefined(void) {
  Obj *t = newObj("TRUE", CL_CONST); t->type = typeBool; t->cval = 1; insertObj(t);
  Obj *f = newObj("FALSE", CL_CONST); f->type = typeBool; f->cval = 0; insertObj(f);
  struct { const char *n; Type *t; } basics[] = {
    {"INTEGER", typeInt}, {"REAL", typeReal}, {"BOOLEAN", typeBool},
    {"CHAR", typeChar}, {"SET", typeSet}, {"LONGINT", typeLongint}
  };
  for (unsigned i = 0; i < sizeof(basics) / sizeof(basics[0]); i++) {
    Obj *o = newObj(basics[i].n, CL_TYPE);
    o->type = basics[i].t;
    insertObj(o);
  }
  int z1[1] = {0};
  int z2[2] = {0, 0};
  insertObj(mkPredefProc("ABS", PD_ABS, 1, z1, (Type *[]){typeInt})); /* polymorphic; checked at use */
  insertObj(mkPredefProc("ODD", PD_ODD, 1, z1, (Type *[]){typeInt}));
  insertObj(mkPredefProc("LEN", PD_LEN, 2, z2, (Type *[]){typeCharArrayAny, typeInt}));
  insertObj(mkPredefProc("ORD", PD_ORD, 1, z1, (Type *[]){typeChar}));
  insertObj(mkPredefProc("CHR", PD_CHR, 1, z1, (Type *[]){typeInt}));
  insertObj(mkPredefProc("ENTIER", PD_ENTIER, 1, z1, (Type *[]){typeReal}));
  insertObj(mkPredefProc("FLOOR", PD_FLOOR, 1, z1, (Type *[]){typeReal}));
  insertObj(mkPredefProc("NEW", PD_NEW, 1, z1, (Type *[]){typeCharArrayAny}));
  { int z1v[1] = {1};
    insertObj(mkPredefProc("DISPOSE", PD_DISPOSE, 1, z1v, (Type *[]){typeAnyPointer})); }
  insertObj(mkPredefProc("INC", PD_INC, 2, z2, (Type *[]){typeInt, typeInt}));
  insertObj(mkPredefProc("DEC", PD_DEC, 2, z2, (Type *[]){typeInt, typeInt}));
  insertObj(mkPredefProc("INCL", PD_INCL, 2, z2, (Type *[]){typeSet, typeInt}));
  insertObj(mkPredefProc("EXCL", PD_EXCL, 2, z2, (Type *[]){typeSet, typeInt}));
  insertObj(mkPredefProc("COPY", PD_COPY, 2, z2, (Type *[]){typeCharArrayAny, typeCharArrayAny}));
  insertObj(mkPredefProc("HALT", PD_HALT, 1, z1, (Type *[]){typeInt}));
  insertObj(mkPredefProc("CAP", PD_CAP, 1, z1, (Type *[]){typeChar}));
  /* bit-casts for threaded code (ext): identity, no code emitted */
  { Obj *o = mkPredefProc("PROCV", PD_PROCV, 1, z1, (Type *[]){typeLongint}); o->type = typeProc0; insertObj(o); }
  { Obj *o = mkPredefProc("PROCC", PD_PROCC, 1, z1, (Type *[]){typeProc0}); o->type = typeLongint; insertObj(o); }
}

static Obj *mkBuiltinProc(const char *nm, int id, int nparams, int *varFlags, Type **ptypes) {
  Obj *o = newObj(nm, CL_PROC);
  o->procIndex = id;
  o->level = 0;
  o->nparams = nparams;
  o->params = NULL;
  Obj **tail = &o->params;
  for (int i = 0; i < nparams; i++) {
    Obj *p = newObj("", CL_VAR);
    p->type = ptypes[i];
    p->isVarParam = varFlags[i];
    *tail = p; tail = &p->nextParam;
  }
  return o;
}

static void makeBuiltinModules(void) {
  Obj *out = newObj("Out", CL_MODULE);
  out->modId = 255; out->builtin = 1;
  int zv[2] = {0, 0}, vv[1] = {1};
  Obj **t = &out->members;
  *t = mkBuiltinProc("Int", B_OUT_INT, 2, zv, (Type *[]){typeInt, typeInt}); t = &(*t)->next;
  *t = mkBuiltinProc("Real", B_OUT_REAL, 2, zv, (Type *[]){typeReal, typeInt}); t = &(*t)->next;
  *t = mkBuiltinProc("Char", B_OUT_CHAR, 1, zv, (Type *[]){typeChar}); t = &(*t)->next;
  *t = mkBuiltinProc("String", B_OUT_STRING, 1, zv, (Type *[]){typeCharArrayAny}); t = &(*t)->next;
  *t = mkBuiltinProc("Long", B_OUT_LONG, 2, zv, (Type *[]){typeLongint, typeInt}); t = &(*t)->next;
  *t = mkBuiltinProc("Byte", B_OUT_BYTE, 1, zv, (Type *[]){typeInt}); t = &(*t)->next;
  *t = mkBuiltinProc("Ln", B_OUT_LN, 0, zv, NULL); t = &(*t)->next;
  builtinOut = out;

  Obj *in = newObj("In", CL_MODULE);
  in->modId = 255; in->builtin = 1;
  t = &in->members;
  *t = mkBuiltinProc("Int", B_IN_INT, 1, vv, (Type *[]){typeInt}); t = &(*t)->next;
  *t = mkBuiltinProc("Real", B_IN_REAL, 1, vv, (Type *[]){typeReal}); t = &(*t)->next;
  *t = mkBuiltinProc("Char", B_IN_CHAR, 1, vv, (Type *[]){typeChar}); t = &(*t)->next;
  *t = mkBuiltinProc("Line", B_IN_LINE, 1, vv, (Type *[]){typeCharArrayAny}); t = &(*t)->next;
  *t = mkBuiltinProc("Byte", B_IN_BYTE, 1, vv, (Type *[]){typeInt}); t = &(*t)->next;
  builtinIn = in;

  /* Files module: opaque File = POINTER TO FileDesc(handle: LONGINT, eof: BOOLEAN) */
  Obj *files = newObj("Files", CL_MODULE);
  files->modId = 255; files->builtin = 1;
  Obj **ft = &files->members;
  Type *fileDesc = mkRecordType();
  Field *fh = calloc(1, sizeof(Field)); strcpy(fh->name, "handle"); fh->type = typeLongint;
  Field *fe = calloc(1, sizeof(Field)); strcpy(fe->name, "eof"); fe->type = typeBool;
  fh->next = fe;
  completeRecord(fileDesc, NULL, fh, 2);
  Type *filePtr = mkPointerType(fileDesc);
  strcpy(filePtr->name, "File");
  Obj *fto = newObj("File", CL_TYPE);
  fto->type = filePtr;
  *ft = fto; ft = &(*ft)->next;
  int z3[3] = {0, 0, 0};
  *ft = mkBuiltinProc("Open", B_FILES_OPEN, 1, z3, (Type *[]){typeCharArrayAny}); (*ft)->type = filePtr; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Create", B_FILES_CREATE, 1, z3, (Type *[]){typeCharArrayAny}); (*ft)->type = filePtr; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Close", B_FILES_CLOSE, 1, z3, (Type *[]){filePtr}); ft = &(*ft)->next;
  *ft = mkBuiltinProc("ReadByte", B_FILES_READBYTE, 1, z3, (Type *[]){filePtr}); (*ft)->type = typeInt; ft = &(*ft)->next;
  *ft = mkBuiltinProc("WriteByte", B_FILES_WRITEBYTE, 2, z3, (Type *[]){filePtr, typeInt}); ft = &(*ft)->next;
  *ft = mkBuiltinProc("Read", B_FILES_READ, 3, z3, (Type *[]){filePtr, typeCharArrayAny, typeInt}); (*ft)->type = typeInt; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Write", B_FILES_WRITE, 3, z3, (Type *[]){filePtr, typeCharArrayAny, typeInt}); ft = &(*ft)->next;
  *ft = mkBuiltinProc("Eof", B_FILES_EOF, 1, z3, (Type *[]){filePtr}); (*ft)->type = typeBool; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Length", B_FILES_LENGTH, 1, z3, (Type *[]){filePtr}); (*ft)->type = typeLongint; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Pos", B_FILES_POS, 1, z3, (Type *[]){filePtr}); (*ft)->type = typeLongint; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Set", B_FILES_SET, 2, z3, (Type *[]){filePtr, typeLongint}); ft = &(*ft)->next;
  *ft = mkBuiltinProc("Delete", B_FILES_DELETE, 1, z3, (Type *[]){typeCharArrayAny}); (*ft)->type = typeBool; ft = &(*ft)->next;
  *ft = mkBuiltinProc("Exists", B_FILES_EXISTS, 1, z3, (Type *[]){typeCharArrayAny}); (*ft)->type = typeBool; ft = &(*ft)->next;
  builtinFiles = files;

  /* SYSTEM module: low-level OS interface (see docs/AUTOHEBERGEMENT.md) */
  Obj *system = newObj("SYSTEM", CL_MODULE);
  system->modId = 255; system->builtin = 1;
  Obj **st = &system->members;
  Type *ll[2] = {typeLongint, typeLongint};
  *st = mkBuiltinProc("BAND", B_SYS_BAND, 2, zv, ll); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("BOR", B_SYS_BOR, 2, zv, ll); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("BXOR", B_SYS_BXOR, 2, zv, ll); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("BNOT", B_SYS_BNOT, 1, zv, (Type *[]){typeLongint}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("LSH", B_SYS_LSH, 2, zv, ll); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("ROT", B_SYS_ROT, 2, zv, ll); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("BIT", B_SYS_BIT, 2, zv, ll); (*st)->type = typeBool; st = &(*st)->next;
  *st = mkBuiltinProc("ARGC", B_SYS_ARGC, 0, zv, NULL); (*st)->type = typeInt; st = &(*st)->next;
  int av[2] = {0, 1};
  *st = mkBuiltinProc("ARGV", B_SYS_ARGV, 2, av, (Type *[]){typeInt, typeCharArrayAny}); st = &(*st)->next;
  *st = mkBuiltinProc("TICKS", B_SYS_TICKS, 0, zv, NULL); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("EXIT", B_SYS_EXIT, 1, zv, (Type *[]){typeInt}); st = &(*st)->next;
  /* casts — needed by VM.Mod (guest cells are LONGINT, builtins want INTEGER/REAL) */
  *st = mkBuiltinProc("L2I", B_SYS_L2I, 1, zv, (Type *[]){typeLongint}); (*st)->type = typeInt; st = &(*st)->next;
  *st = mkBuiltinProc("REALBITS", B_SYS_REALBITS, 1, zv, (Type *[]){typeReal}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("BITSREAL", B_SYS_BITSREAL, 1, zv, (Type *[]){typeLongint}); (*st)->type = typeReal; st = &(*st)->next;
  *st = mkBuiltinProc("I2REAL", B_SYS_I2REAL, 1, zv, (Type *[]){typeInt}); (*st)->type = typeReal; st = &(*st)->next;
  /* FFI generique (src/ffi_glue.c, ids 80..89) : DLL loadables + appel C + mémoire C */
  { int z10[10] = {0,0,0,0,0,0,0,0,0,0};
    Type *callcT[10] = {typeLongint, typeInt, typeLongint, typeLongint, typeLongint,
                        typeLongint, typeLongint, typeLongint, typeLongint, typeLongint};
    *st = mkBuiltinProc("CALLC", B_FFI_CALLC, 10, z10, callcT); (*st)->type = typeLongint; st = &(*st)->next; }
  *st = mkBuiltinProc("LOADLIB", B_FFI_LOADLIB, 1, zv, (Type *[]){typeCharArrayAny}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("SYMBOL", B_FFI_SYMBOL, 2, zv, (Type *[]){typeLongint, typeCharArrayAny}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("FREELIB", B_FFI_FREELIB, 1, zv, (Type *[]){typeLongint}); st = &(*st)->next;
  *st = mkBuiltinProc("CSTR", B_FFI_CSTR, 1, zv, (Type *[]){typeCharArrayAny}); (*st)->type = typeLongint; st = &(*st)->next;
  { int v2[2] = {0, 1};
    *st = mkBuiltinProc("STR", B_FFI_STR, 2, v2, (Type *[]){typeLongint, typeCharArrayAny}); st = &(*st)->next; }
  *st = mkBuiltinProc("MALLOC", B_FFI_MALLOC, 1, zv, (Type *[]){typeLongint}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("FREE", B_FFI_FREE, 1, zv, (Type *[]){typeLongint}); st = &(*st)->next;
  *st = mkBuiltinProc("PEEK", B_FFI_PEEK, 1, zv, (Type *[]){typeLongint}); (*st)->type = typeLongint; st = &(*st)->next;
  *st = mkBuiltinProc("POKE", B_FFI_POKE, 2, zv, (Type *[]){typeLongint, typeLongint}); st = &(*st)->next;
  { int g2[2] = {0, 1};
    *st = mkBuiltinProc("GETENV", B_FFI_GETENV, 2, g2, (Type *[]){typeCharArrayAny, typeCharArrayAny});
    (*st)->type = typeBool; st = &(*st)->next; }
  { int v1b[1] = {1};
    *st = mkBuiltinProc("EXEPATH", B_FFI_EXEPATH, 1, v1b, (Type *[]){typeCharArrayAny});
    (*st)->type = typeInt; st = &(*st)->next; }
  builtinSystem = system;
}

/* ---------- imports ---------- */
static void installImport(const char *real, const char *alias, const char *dir) {
  int modId;
  if (!strcmp(real, "Out") || !strcmp(real, "In") || !strcmp(real, "Files") || !strcmp(real, "SYSTEM")) {
    Obj *src = !strcmp(real, "Out") ? builtinOut
             : (!strcmp(real, "In") ? builtinIn
             : (!strcmp(real, "Files") ? builtinFiles : builtinSystem));
    Obj *cp = newObj(alias, CL_MODULE);
    cp->modId = 255; cp->builtin = 1; cp->members = src->members;
    insertObj(cp);
    return;
  }
  /* search path: dir of the importing file, then dir/../lib, dir/../../lib (project lib/) */
  char path[600], mp[600], cdir[600];
  static char sdirs[80][600];
  int ndirs = obSearchDirs(dir, sdirs, 80);
  int found = 0;
  for (int ci = 0; ci < ndirs && !found; ci++) {
    snprintf(cdir, sizeof cdir, "%s", sdirs[ci]);
    snprintf(path, sizeof path, "%s/%s.obc", cdir, real);
    snprintf(mp, sizeof mp, "%s/%s.Mod", cdir, real);
    if (fileExists(path)) {
      found = 1;
    } else if (fileExists(mp)) {
      /* compile recursively, preserving all compiler/lexer state */
      LexState ls;
      lexSave(&ls);
      Module *savedMod = curMod;
      Proc *savedProc = curProc;
      int savedScopeTop = scopeTop;
      Obj *savedScopes[64];
      memcpy(savedScopes, scopeStack, sizeof scopeStack);
      int savedLevel = curLevel;
      ImpEnt savedCache[64];
      int savedN = nImpCache;
      memcpy(savedCache, impCache, sizeof impCache);
      int ok = compileFile(mp, path, cdir);
      lexRestore(&ls);
      curMod = savedMod; curProc = savedProc;
      scopeTop = savedScopeTop;
      memcpy(scopeStack, savedScopes, sizeof scopeStack);
      curLevel = savedLevel;
      nImpCache = savedN;
      memcpy(impCache, savedCache, sizeof impCache);
      if (!ok) obError(line, "failed to compile imported module '%s'", real);
      found = 1;
    }
  }
  if (!found) obError(line, "cannot find module '%s' (.obc or .Mod) in '%s' or its lib dirs", real, dir);
  /* cache lookup */
  LoadedModule *lm = NULL;
  int cachedModId = 0;
  for (int i = 0; i < nImpCache; i++)
    if (!strcmp(impCache[i].name, real)) { lm = impCache[i].lm; cachedModId = impCache[i].modId; break; }
  if (!lm) {
    lm = loadModuleFile(path);
    if (!lm) obError(line, "bad .obc file for module '%s'", real);
    if (nImpCache < 64) {
      strcpy(impCache[nImpCache].name, real);
      impCache[nImpCache].lm = lm;
      impCache[nImpCache].modId = 0; /* set below */
      nImpCache++;
    }
  }
  modId = curMod->nimports + 1;
  if (curMod->nimports >= curMod->capimports) {
    curMod->capimports = curMod->capimports * 2 + 4;
    curMod->imports = realloc(curMod->imports, curMod->capimports * sizeof(char *));
  }
  curMod->imports[curMod->nimports] = strdup(real);
  curMod->nimports++;
  for (int i = 0; i < nImpCache; i++)
    if (impCache[i].lm == lm) impCache[i].modId = modId;
  Obj *mo = moduleObjFromLoaded(lm, modId, 1);
  strcpy(mo->name, alias);
  /* set defMod/defTypeIdx on type members */
  for (Obj *m = mo->members; m; m = m->next) {
    if (m->cls == CL_TYPE) {
      m->defMod = modId;
      for (int j = 0; j < lm->ntypes; j++)
        if (lm->types[j] == m->type) { m->defTypeIdx = j; break; }
    }
    if (m->cls == CL_VAR) m->modId = modId;
  }
  insertObj(mo);
  (void)cachedModId;
}

static void parseImports(const char *dir) {
  for (;;) {
    char alias[64], real[64];
    readIdent(alias);
    strcpy(real, alias);
    if (accept(S_ASSIGN)) { readIdent(real); }
    installImport(real, alias, dir);
    if (!accept(S_COMMA)) break;
  }
  expect(S_SEMI);
}

/* ---------- constant expressions ---------- */
static Cell constFactor(Type **t);

static Cell foldIntOp(int op, Cell a, Cell b) {
  switch (op) {
    case S_PLUS: return a + b;
    case S_MINUS: return a - b;
    case S_STAR: return a * b;
    case S_DIV: { Cell q = a / b, r = a % b; if (r && ((r < 0) != (b < 0))) q--; return q; }
    case S_MOD: { Cell r = a % b; if (r && ((r < 0) != (b < 0))) r += b; return r; }
    default: obError(line, "bad const op"); return 0;
  }
}

static Cell constTerm(Type **t) {
  Cell v = constFactor(t);
  while (sym == S_STAR || sym == S_SLASH || sym == S_DIV || sym == S_MOD || sym == S_AMP) {
    int op = sym; nextSym();
    Type *t2; Cell v2 = constFactor(&t2);
    if (op == S_AMP) { v = (v && v2); *t = typeBool; }
    else if (op == S_SLASH) {
      double d = (t && *t == typeReal) ? cellToDouble(v) : (double)v;
      double d2 = (t2 == typeReal) ? cellToDouble(v2) : (double)v2;
      v = cellFromDouble(d / d2); *t = typeReal;
    } else {
      if ((*t == typeSet) && (t2 == typeSet)) {
        if (op == S_STAR) v = v & v2; else if (op == S_MINUS) v = v & ~v2; else v = v | v2;
      } else if (*t == typeReal || t2 == typeReal) {
        double d = (*t == typeReal) ? cellToDouble(v) : (double)v;
        double d2 = (t2 == typeReal) ? cellToDouble(v2) : (double)v2;
        double r = 0;
        switch (op) { case S_PLUS: r = d + d2; break; case S_MINUS: r = d - d2; break;
                      case S_STAR: r = d * d2; break; default: r = d / d2; }
        v = cellFromDouble(r); *t = typeReal;
      } else {
        v = foldIntOp(op, v, v2);
        *t = (*t == typeLongint || t2 == typeLongint) ? typeLongint : typeInt;
      }
    }
  }
  return v;
}

static Cell constSimple(Type **t) {
  int neg = 0;
  if (sym == S_PLUS) nextSym();
  else if (sym == S_MINUS) { neg = 1; nextSym(); }
  Cell v = constTerm(t);
  if (neg) {
    if (*t == typeReal) v = cellFromDouble(-cellToDouble(v));
    else v = -v;
  }
  while (sym == S_PLUS || sym == S_MINUS || sym == S_OR) {
    int op = sym; nextSym();
    Type *t2; Cell v2 = constTerm(&t2);
    if (op == S_OR) { v = (v || v2); *t = typeBool; }
    else if (*t == typeReal || t2 == typeReal) {
      double d = (*t == typeReal) ? cellToDouble(v) : (double)v;
      double d2 = (t2 == typeReal) ? cellToDouble(v2) : (double)v2;
      v = cellFromDouble(op == S_PLUS ? d + d2 : d - d2); *t = typeReal;
    } else if (*t == typeSet && t2 == typeSet) {
      v = (op == S_PLUS) ? (v | v2) : (v & ~v2);
    } else {
      v = foldIntOp(op, v, v2);
      *t = (*t == typeLongint || t2 == typeLongint) ? typeLongint : typeInt;
    }
  }
  return v;
}

static Cell constFactor(Type **t) {
  if (sym == S_INT) {
    Cell v = ival; nextSym();
    if (v > INT32_MAX || v < INT32_MIN) { *t = typeLongint; return v; }
    *t = typeInt; return v;
  }
  if (sym == S_REAL) { *t = typeReal; Cell v = cellFromDouble(rval); nextSym(); return v; }
  if (sym == S_CHAR) { *t = typeChar; Cell v = cval; nextSym(); return v; }
  if (sym == S_NIL) { *t = typeNil; nextSym(); return 0; }
  if (sym == S_LPAREN) { nextSym(); Cell v = constSimple(t); expect(S_RPAREN); return v; }
  if (sym == S_TILDE) { nextSym(); *t = typeBool; return !constFactor(t); }
  if (sym == S_LBRACE) {
    nextSym();
    Cell s = 0; *t = typeSet;
    if (sym != S_RBRACE) {
      for (;;) {
        Type *t1; Cell a = constSimple(&t1);
        if (accept(S_DOTDOT)) {
          Type *t2; Cell b = constSimple(&t2);
          for (Cell i = a; i <= b && i < 32; i++) s |= (Cell)1 << i;
        } else {
          if (a >= 0 && a < 32) s |= (Cell)1 << a;
        }
        if (!accept(S_COMMA)) break;
      }
    }
    expect(S_RBRACE);
    return s;
  }
  if (sym == S_IDENT) {
    char n[64]; strcpy(n, name); nextSym();
    Obj *o = lookup(n);
    if (!o || o->cls != CL_CONST) obError(line, "'%s' is not a constant", n);
    *t = o->type;
    return o->cval;
  }
  obError(line, "expected constant expression, got %s", symName(sym));
  return 0;
}

static Cell parseConstExpr(Type **t) {
  Cell v = constSimple(t);
  if (sym == S_EQ || sym == S_NEQ || sym == S_LT || sym == S_LE || sym == S_GT || sym == S_GE) {
    int op = sym; nextSym();
    Type *t2; Cell v2 = constSimple(&t2);
    int r = 0;
    if (*t == typeReal || t2 == typeReal) {
      double a = (*t == typeReal) ? cellToDouble(v) : (double)v;
      double b = (t2 == typeReal) ? cellToDouble(v2) : (double)v2;
      switch (op) { case S_EQ: r = a == b; break; case S_NEQ: r = a != b; break;
                    case S_LT: r = a < b; break; case S_LE: r = a <= b; break;
                    case S_GT: r = a > b; break; case S_GE: r = a >= b; break; }
    } else {
      switch (op) { case S_EQ: r = v == v2; break; case S_NEQ: r = v != v2; break;
                    case S_LT: r = v < v2; break; case S_LE: r = v <= v2; break;
                    case S_GT: r = v > v2; break; case S_GE: r = v >= v2; break; }
    }
    *t = typeBool;
    return r;
  }
  return v;
}

/* ---------- types ---------- */
static Type *parseQualType(void) {
  char n1[64];
  readIdent(n1);
  Obj *o = lookup(n1);
  if (o && o->cls == CL_MODULE) {
    expect(S_DOT);
    char n2[64];
    readIdent(n2);
    o = lookupIn(o->members, n2);
  }
  if (!o || o->cls != CL_TYPE) obError(line, "'%s' is not a type", n1);
  return o->type;
}

static int allowOpenArray = 0; /* set while parsing formal parameters */

static Type *parseType(void) {
  if (sym == S_ARRAY) {
    nextSym();
    if (allowOpenArray && sym == S_OF) { /* open array: formal param "ARRAY OF T" */
      nextSym();
      Type *e = parseType();
      return mkOpenArrayType(e);
    }
    int dims[8], nd = 0;
    for (;;) {
      Type *t; Cell v = parseConstExpr(&t);
      if (t != typeInt || v <= 0 || v > 100000000) obError(line, "bad array dimension");
      if (nd >= 8) obError(line, "too many dimensions");
      dims[nd++] = (int)v;
      if (!accept(S_COMMA)) break;
    }
    expect(S_OF);
    Type *e = parseType();
    return mkArrayType(e, nd, dims);
  }
  if (sym == S_RECORD) {
    nextSym();
    Type *base = NULL;
    if (accept(S_LPAREN)) {
      base = parseQualType();
      if (base->kind != TK_RECORD) obError(line, "base type must be a record");
      expect(S_RPAREN);
    }
    Field *fields = NULL; Field **tail = &fields; int nf = 0;
    while (sym == S_IDENT) {
      char fnames[16][64]; int nn = 0;
      do {
        if (nn >= 16) obError(line, "too many fields in one declaration");
        strcpy(fnames[nn++], name); nextSym();
      } while (accept(S_COMMA));
      expect(S_COLON);
      Type *ft = parseType();
      accept(S_SEMI); /* trailing ';' before END is optional */
      for (int i = 0; i < nn; i++) {
        Field *fl = calloc(1, sizeof(Field));
        strcpy(fl->name, fnames[i]);
        fl->type = ft;
        *tail = fl; tail = &fl->next; nf++;
      }
    }
    expect(S_END);
    Type *rec = mkRecordType();
    completeRecord(rec, base, fields, nf);
    return rec;
  }
  if (sym == S_POINTER) {
    nextSym();
    expect(S_TO);
    if (sym == S_ARRAY) { /* POINTER TO ARRAY n OF T (fixed dims only; open arrays rejected at NEW) */
      Type *to = parseType();
      if (to->kind != TK_ARRAY || to->isOpen) obError(line, "pointer base must be a fixed array or record");
      return mkPointerType(to);
    }
    char n[64];
    readIdent(n);
    Obj *o = lookup(n);
    Type *to;
    if (o && o->cls == CL_TYPE) {
      to = o->type;
    } else {
      /* forward reference: create placeholder record */
      to = mkRecordType();
      strcpy(to->name, n);
      Obj *no = newObj(n, CL_TYPE);
      no->type = to;
      insertObj(no);
    }
    if (o && o->cls == CL_MODULE) obError(line, "module-qualified pointer not supported here");
    if (to->kind != TK_RECORD && to->kind != TK_ARRAY) obError(line, "pointer base must be a record or array");
    if (to->kind == TK_ARRAY && to->isOpen) obError(line, "pointer to open array not allowed");
    return mkPointerType(to);
  }
  if (sym == S_PROCEDURE) { /* procedural type: PROCEDURE (FPSection; ...) [: T] (ext) */
    nextSym();
    Type *pt = mkProcType();
    if (accept(S_LPAREN)) {
      if (sym != S_RPAREN) {
        for (;;) {
          int isVar = accept(S_VAR);
          char names[16][64]; int nn = 0;
          do {
            if (nn >= 16) obError(line, "too many parameter names in procedure type");
            strcpy(names[nn++], name); nextSym();
          } while (accept(S_COMMA));
          expect(S_COLON);
          int savedAllow = allowOpenArray;
          allowOpenArray = 1; /* open arrays allowed in formal params */
          Type *pty = parseType();
          allowOpenArray = savedAllow;
          for (int i = 0; i < nn; i++) {
            Obj *pa = newObj(names[i], CL_VAR);
            pa->type = pty;
            pa->isVarParam = isVar;
            Obj **tail = &pt->params;
            while (*tail) tail = &(*tail)->nextParam;
            *tail = pa;
            pt->nparams++;
          }
          if (!accept(S_SEMI)) break;
        }
      }
      expect(S_RPAREN);
    }
    if (accept(S_COLON)) pt->result = parseType();
    return pt;
  }
  return parseQualType();
}

/* ---------- declarations ---------- */
static void parseConstDecl(void) {
  while (sym == S_IDENT) {
    char n[64]; strcpy(n, name); nextSym();
    int exported = accept(S_STAR);
    expect(S_EQ);
    Type *t; Cell v = parseConstExpr(&t);
    expect(S_SEMI);
    Obj *o = newObj(n, CL_CONST);
    o->type = t; o->cval = v; o->exported = exported;
    o->nextConst = curMod->consts; curMod->consts = o;
    insertObj(o);
  }
}

static void parseTypeDecl(void) {
  while (sym == S_IDENT) {
    char n[64]; strcpy(n, name); nextSym();
    int exported = accept(S_STAR);
    accept(S_MINUS); /* read-only marker ignored */
    expect(S_EQ);
    /* forward placeholder? */
    Obj *existing = lookup(n);
    Type *t;
    if (sym == S_RECORD && existing && existing->cls == CL_TYPE &&
        existing->type->kind == TK_RECORD && existing->type->fields == NULL &&
        existing->type->payload == 0) {
      /* complete the placeholder */
      t = existing->type;
      nextSym(); /* RECORD */
      Type *base = NULL;
      if (accept(S_LPAREN)) {
        base = parseQualType();
        expect(S_RPAREN);
      }
      Field *fields = NULL; Field **tail = &fields; int nf = 0;
      while (sym == S_IDENT) {
        char fnames[16][64]; int nn = 0;
        do { strcpy(fnames[nn++], name); nextSym(); } while (accept(S_COMMA));
        expect(S_COLON);
        Type *ft = parseType();
        accept(S_SEMI);
        for (int i = 0; i < nn; i++) {
          Field *fl = calloc(1, sizeof(Field));
          strcpy(fl->name, fnames[i]); fl->type = ft;
          *tail = fl; tail = &fl->next; nf++;
        }
      }
      expect(S_END);
      completeRecord(t, base, fields, nf);
      strcpy(t->name, n);
    } else {
      t = parseType();
      strcpy(t->name, n);
      Obj *o = newObj(n, CL_TYPE);
      o->type = t;
      o->exported = exported;
      insertObj(o);
    }
    int idx = typeIndex(curMod, t);
    curMod->types[idx].exported = exported;
    expect(S_SEMI);
  }
}

static void parseVarDecl(int isGlobal) {
  while (sym == S_IDENT) {
    char names[16][64]; int nn = 0;
    do {
      if (nn >= 16) obError(line, "too many variables in one declaration");
      strcpy(names[nn++], name); nextSym();
    } while (accept(S_COMMA));
    int exported = accept(S_STAR);
    expect(S_COLON);
    Type *t = parseType();
    expect(S_SEMI);
    for (int i = 0; i < nn; i++) {
      Obj *o = newObj(names[i], CL_VAR);
      o->type = t;
      o->exported = exported;
      int sz = typeSizeCells(t); /* records occupy their payload inline */
      if (isGlobal) {
        o->level = 0;
        o->offset = curMod->globalSize;
        curMod->globalSize += sz;
        o->modId = 0;
        o->nextGlobal = curMod->globals;
        curMod->globals = o;
      } else {
        o->level = curLevel;
        o->offset = curProc->nlocals;
        curProc->nlocals += sz;
        if (t->kind == TK_ARRAY) {
          int m, ix; findTypeRef(t, &m, &ix);
          emitTypeOp(OP_ALLOC_ARRAY, m, ix);
          emit32(OP_STORE_LOCAL, (uint32_t)o->offset);
        }
      }
      insertObj(o);
    }
  }
}

static void parseProcDecl(void);

static void parseDeclarations(int isGlobal) {
  for (;;) {
    if (sym == S_CONST) { nextSym(); parseConstDecl(); }
    else if (sym == S_TYPE) { nextSym(); parseTypeDecl(); }
    else if (sym == S_VAR) { nextSym(); parseVarDecl(isGlobal); }
    else if (sym == S_PROCEDURE) { parseProcDecl(); }
    else break;
  }
}

static Proc *addProc(const char *nm, int exported, int isBody) {
  Module *m = curMod;
  if (m->nprocs >= m->capprocs) {
    m->capprocs = m->capprocs * 2 + 4;
    m->procs = realloc(m->procs, m->capprocs * sizeof(Proc));
  }
  Proc *p = &m->procs[m->nprocs];
  memset(p, 0, sizeof(Proc));
  strncpy(p->name, nm, 63);
  p->exported = exported;
  p->isBody = isBody;
  bufInit(&p->code);
  m->nprocs++;
  return p;
}

static void parseProcDecl(void) {
  expect(S_PROCEDURE);
  char pname[64];
  readIdent(pname);
  int exported = accept(S_STAR);
  Obj *po = newObj(pname, CL_PROC);
  po->level = curLevel;
  po->exported = exported;
  po->procIndex = curMod->nprocs;
  insertObj(po);
  int pIdx = curMod->nprocs;
  addProc(pname, exported, 0);
  Proc *p = &curMod->procs[pIdx];
  Proc *savedProc = curProc;
  curProc = p;
  curLevel++;
  scopePush();
  /* parameters */
  if (accept(S_LPAREN)) {
    if (sym != S_RPAREN) {
      for (;;) {
        int isVar = accept(S_VAR);
        char names[16][64]; int nn = 0;
        do { strcpy(names[nn++], name); nextSym(); } while (accept(S_COMMA));
        expect(S_COLON);
        int savedAllowOpen = allowOpenArray;
        allowOpenArray = 1; /* formal params may be open arrays: ARRAY OF T */
        Type *pt = parseType();
        allowOpenArray = savedAllowOpen;
        for (int i = 0; i < nn; i++) {
          Obj *pa = newObj(names[i], CL_VAR);
          pa->type = pt;
          pa->isVarParam = isVar;
          pa->level = curLevel;
          pa->offset = p->nlocals++;
          if (p->nparams >= p->capparams) {
            p->capparams = p->capparams * 2 + 4;
            p->params = realloc(p->params, p->capparams * sizeof(Obj *));
          }
          p->params[p->nparams++] = pa;
          Obj **tail = &po->params;
          while (*tail) tail = &(*tail)->nextParam;
          *tail = pa;
          insertObj(pa);
        }
        if (!accept(S_SEMI)) break;
      }
    }
    expect(S_RPAREN);
  }
  if (accept(S_COLON)) {
    p->hasResult = 1;
    p->result = parseType();
    po->type = p->result;
  }
  expect(S_SEMI);
  po->nparams = curProc->nparams;
  parseDeclarations(0);
  curProc = &curMod->procs[pIdx]; /* procs array may have been reallocated */
  if (accept(S_BEGIN)) parseStatements();
  emit(OP_RET);
  expect(S_END);
  if (sym == S_IDENT) { nextSym(); }
  expect(S_SEMI);
  scopePop();
  curLevel--;
  curProc = savedProc;
}

/* ---------- designators ---------- */
static Obj *readFirstIdent(int *mod) {
  char n1[64];
  readIdent(n1);
  Obj *o = lookup(n1);
  if (!o) obError(line, "undefined identifier '%s'", n1);
  *mod = 0;
  if (o->cls == CL_MODULE) {
    *mod = o->modId;
    expect(S_DOT);
    char n2[64];
    readIdent(n2);
    o = lookupIn(o->members, n2);
    if (!o) obError(line, "'%s' is not exported by module '%s'", n2, n1);
  }
  return o;
}

/* parse selectors after first ident; mode M_VAL/M_ADDR/M_VARARG.
   st: 0 = stack top is a value, 1 = stack top is a tagged address of storage */
static int gDesigHdr; /* header cells before the payload of the last designator's record addr (2 heap, 0 inline) */

static Type *parseDesignator(int mode, Obj *o, int mod) {
  Type *t = o->type;
  int st = 0;
  int hdr = 0; /* 2 if the record address points to a heap object header, 0 if payload start */
  gDesigHdr = 0;
  switch (o->cls) {
    case CL_CONST:
      if (t->kind == TK_REAL) { emit(OP_CONST_R); bufU64(&curProc->code, (uint64_t)o->cval); }
      else if (t->kind == TK_LONGINT) { emit(OP_CONST_L); bufU64(&curProc->code, (uint64_t)o->cval); }
      else emit32(OP_CONST_I, (uint32_t)(int32_t)o->cval);
      return t;
    case CL_VAR:
      if (o->level == 0) {
        if (mode == M_VAL) {
          if (t->kind == TK_RECORD) { emitGlobalOp(OP_ADDR_GLOBAL, mod, o->offset); st = 1; }
          else { emitGlobalOp(OP_LOAD_GLOBAL, mod, o->offset); st = 0; }
        } else { emitGlobalOp(OP_ADDR_GLOBAL, mod, o->offset); st = 1; }
      } else {
        uint32_t op = (uint32_t)(((curLevel - o->level) << 16) | (o->offset & 0xFFFF));
        if (o->isVarParam) {
          emit32(OP_ADDR_LOCAL, op);
          emit(OP_LOAD_AT); /* effective address passed by caller */
          st = 1;
          if (mode == M_VAL) {
            if (t->kind == TK_ARRAY || t->kind == TK_POINTER) { emit(OP_LOAD_AT); }
            else if (t->kind == TK_RECORD) { /* value is the record addr already */ }
            else { emit(OP_LOAD_AT); }
            st = 0;
          }
        } else {
          if (mode == M_VAL) {
            if (t->kind == TK_RECORD) { emit32(OP_ADDR_LOCAL, op); st = 1; } /* record value = its address */
            else { emit32(OP_LOAD_LOCAL, op); st = 0; }
          } else { emit32(OP_ADDR_LOCAL, op); st = 1; }
        }
      }
      break;
    default:
      obError(line, "'%s' is not a variable", o->name);
  }
  /* selectors */
  int addrIsPayload = 0; /* st==1 but the address is already a payload start
                            (inline array field / array element), not a slot holding a ref */
  for (;;) {
    if (sym == S_DOT) {
      nextSym();
      char fname[64];
      readIdent(fname);
      int h = hdr;
      if (t->kind == TK_POINTER && t->to->kind == TK_RECORD) {
        if (st == 1) { emit(OP_LOAD_AT); } /* slot addr -> ref */
        emit(OP_TO_ADDR); /* ref -> obj addr */
        st = 1;
        t = t->to;
        h = 2; /* heap object: [tag, payload, fields...] */
      }
      if (t->kind != TK_RECORD) obError(line, "field selection on non-record");
      Field *fl = findField(t, fname);
      if (!fl) obError(line, "no field '%s'", fname);
      emit32(OP_CONST_I, (uint32_t)(h + fl->offset));
      emit(OP_AADD); /* record addr + hdr + off = field addr */
      st = 1;
      t = fl->type;
      hdr = 0; /* field addresses are payload starts (inline) */
      addrIsPayload = (t->kind == TK_ARRAY); /* inline array field: addr is its payload start */
    } else if (sym == S_CARET) {
      nextSym();
      if (t->kind != TK_POINTER) obError(line, "dereference of non-pointer");
      if (st == 1) emit(OP_LOAD_AT);
      if (t->to->kind == TK_RECORD) { emit(OP_TO_ADDR); st = 1; hdr = 2; }
      else st = 0; /* pointer to array: ref is already the value */
      t = t->to;
    } else if (sym == S_LPAREN) {
      /* type guard in designator: p(T) */
      nextSym();
      Type *rt = parseQualType();
      expect(S_RPAREN);
      Type *rec = (rt->kind == TK_POINTER) ? rt->to : rt;
      if (t->kind != TK_POINTER || rec->kind != TK_RECORD) obError(line, "bad type guard");
      if (st == 1) emit(OP_LOAD_AT);
      int m, ix; findTypeRef(rec, &m, &ix);
      emitTypeOp(OP_CHECKTYPE, m, ix);
      t = (rt->kind == TK_POINTER) ? rt : mkPointerType(rec);
      st = 0;
    } else if (sym == S_LBRACK) {
      if (t->kind == TK_POINTER && t->to && t->to->kind == TK_ARRAY) {
        /* implicit deref: p[i] with p: POINTER TO ARRAY */
        if (st == 1) { emit(OP_LOAD_AT); st = 0; } /* slot addr -> ref */
        t = t->to;
      }
      if (t->kind != TK_ARRAY) obError(line, "indexing non-array");
      if (st == 1 && !addrIsPayload) { emit(OP_LOAD_AT); st = 0; } /* slot addr -> ref (inline field: already payload) */
      int nd = t->ndim;
      emit32(OP_CONST_I, 0); /* accumulator */
      int k = 0;
      while (sym == S_LBRACK) {
        nextSym();
        for (;;) {
          if (k >= nd) obError(line, "too many indices");
          Type *it = parseExpression();
          if (it != typeInt) obError(line, "index must be INTEGER");
          /* acc = acc*dims[k] + e : stack [acc, e] */
          emit(OP_SWAP);
          emit32(OP_CONST_I, (uint32_t)t->dims[k]);
          emit(OP_IMUL);
          emit(OP_SWAP);
          emit(OP_IADD);
          k++;
          if (!accept(S_COMMA)) break;
        }
        expect(S_RBRACK);
      }
      if (k != nd) obError(line, "wrong number of indices");
      /* stack: [ref, acc] ; for record elements, acc is in elements -> convert to cells */
      if (t->elem->kind == TK_RECORD) {
        emit32(OP_CONST_I, (uint32_t)typeElemCells(t->elem));
        emit(OP_IMUL);
      }
      if (addrIsPayload) {
        /* inline array (record field / record element): the address on the stack is
           already the payload start -> elem addr = payload + acc (acc already in cells) */
        emit(OP_AADD);
      } else {
        emit(OP_ELEM_ADDR);
      }
      st = 1;
      t = t->elem;
      hdr = 0; /* element addresses are payload starts (no per-element header) */
      addrIsPayload = (t->kind == TK_ARRAY); /* element that is itself an inline array */
    } else break;
  }
  /* final mode conversion */
  gDesigHdr = hdr;
  if (mode == M_VAL) {
    if (st == 1) {
      if (t->kind == TK_RECORD) { /* record value = its address */ }
      else emit(OP_LOAD_AT);
      st = 0;
    }
  } else if (mode == M_ADDR) {
    if (t->kind == TK_ARRAY) {
      if (addrIsPayload) {
        /* inline array field/element: the address on the stack IS the payload start */
      } else {
        /* st==1 slot addr (or elem addr); get ref then payload addr */
        if (st == 1) emit(OP_LOAD_AT); /* -> ref */
        emit(OP_TO_ADDR);
        emit32(OP_CONST_I, (uint32_t)(t->ndim + 2));
        emit(OP_AADD);
      }
    } else if (t->kind == TK_RECORD) {
      emit32(OP_CONST_I, (uint32_t)hdr);
      emit(OP_AADD);
    }
  } /* M_VARARG: leave as-is */
  return t;
}

/* ---------- expressions ---------- */
static void emitRelation(int op, Type *a, Type *b) {
  int mixed = (a == typeReal && b == typeInt) || (a == typeInt && b == typeReal);
  if (mixed) { /* convert the INTEGER side (ext) */
    if (a == typeInt) { emit(OP_SWAP); emit(OP_I2F); emit(OP_SWAP); } else emit(OP_I2F);
  }
  int isReal = (a == typeReal && b == typeReal) || mixed;
  int isNum = (a == typeInt && b == typeInt) || (a == typeChar && b == typeChar);
  int isLong = isIntLike(a) && isIntLike(b) && (a == typeLongint || b == typeLongint);
  switch (op) {
    case S_EQ:
      if (isReal) emit(OP_FEQ); else emit(OP_EQ); return;
    case S_NEQ:
      if (isReal) emit(OP_FNE); else emit(OP_NE); return;
    case S_LT:
      if (isReal) emit(OP_FLT); else if (isLong) emit(OP_LLT); else if (isNum) emit(OP_ILT); else obError(line, "bad operands for <"); return;
    case S_LE:
      if (isReal) emit(OP_FLE); else if (isLong) emit(OP_LLE); else if (isNum) emit(OP_ILE); else obError(line, "bad operands for <="); return;
    case S_GT:
      if (isReal) emit(OP_FGT); else if (isLong) emit(OP_LGT); else if (isNum) emit(OP_IGT); else obError(line, "bad operands for >"); return;
    case S_GE:
      if (isReal) emit(OP_FGE); else if (isLong) emit(OP_LGE); else if (isNum) emit(OP_IGE); else obError(line, "bad operands for >="); return;
    case S_IN:
      if ((a == typeInt || a == typeChar) && b == typeSet) { emit(OP_SET_MEMBER); return; }
      obError(line, "IN requires INTEGER/CHAR and SET"); return;
    case S_IS:
      obError(line, "IS handled separately"); return;
  }
}

static Type *parseExpression(void) {
  Type *t = parseSimpleExpr();
  if (sym == S_EQ || sym == S_NEQ || sym == S_LT || sym == S_LE || sym == S_GT || sym == S_GE ||
      sym == S_IN || sym == S_IS) {
    int op = sym; nextSym();
    if (op == S_IS) {
      Type *rt = parseQualType();
      Type *rec = (rt->kind == TK_POINTER) ? rt->to : rt;
      if (t->kind != TK_POINTER || rec->kind != TK_RECORD) obError(line, "IS requires pointer and record type");
      int m, ix; findTypeRef(rec, &m, &ix);
      emitTypeOp(OP_ISTYPE, m, ix);
      return typeBool;
    }
    Type *t2 = parseSimpleExpr();
    /* type checks */
    if (op == S_IN) { /* checked in emitRelation */ }
    else if (!((isIntLike(t) && isIntLike(t2)) || (t == typeReal && t2 == typeReal) ||
               (t == typeReal && t2 == typeInt) || (t == typeInt && t2 == typeReal) ||
               (t == typeChar && t2 == typeChar) || (t == typeBool && t2 == typeBool && (op == S_EQ || op == S_NEQ)) ||
               (t == typeSet && t2 == typeSet && (op == S_EQ || op == S_NEQ)) ||
               ((t->kind == TK_POINTER || t->kind == TK_NIL) && (t2->kind == TK_POINTER || t2->kind == TK_NIL) && (op == S_EQ || op == S_NEQ)) ||
               ((t->kind == TK_PROC || t->kind == TK_NIL) && (t2->kind == TK_PROC || t2->kind == TK_NIL) && (op == S_EQ || op == S_NEQ)) ||
               (t->kind == TK_PROC && t2->kind == TK_PROC && (op == S_EQ || op == S_NEQ)))) /* proc var = proc var / NIL (ext) */
      obError(line, "incompatible types in comparison");
    emitRelation(op, t, t2);
    t = typeBool;
  }
  return t;
}

static Type *parseSimpleExpr(void) {
  int neg = 0;
  if (sym == S_PLUS) nextSym();
  else if (sym == S_MINUS) { neg = 1; nextSym(); }
  Type *t = parseTerm();
  if (neg) {
    if (t == typeInt) emit(OP_INEG);
    else if (t == typeLongint) emit(OP_LNEG);
    else if (t == typeReal) emit(OP_FNEG);
    else obError(line, "unary minus on non-number");
  }
  while (sym == S_PLUS || sym == S_MINUS || sym == S_OR) {
    int op = sym; nextSym();
    Type *t2 = parseTerm();
    if (op == S_OR) {
      if (t != typeBool || t2 != typeBool) obError(line, "OR requires BOOLEAN");
      emit(OP_OR);
    } else if (isIntLike(t) && isIntLike(t2) && (t == typeLongint || t2 == typeLongint)) {
      emit(op == S_PLUS ? OP_LADD : OP_LSUB);
    } else if (t == typeInt && t2 == typeInt) {
      emit(op == S_PLUS ? OP_IADD : OP_ISUB);
    } else if (t == typeReal && t2 == typeReal) {
      emit(op == S_PLUS ? OP_FADD : OP_FSUB);
    } else if ((t == typeReal && t2 == typeInt) || (t == typeInt && t2 == typeReal)) {
      /* mixed INTEGER/REAL (ext): convert the INTEGER side, real arithmetic */
      if (t == typeInt) emitI2FBelow(t); else emitI2FTop(t2);
      emit(op == S_PLUS ? OP_FADD : OP_FSUB);
    } else if (t == typeSet && t2 == typeSet) {
      if (op == S_PLUS) emit(OP_SET_UNION); else emit(OP_SET_DIFF);
    } else {
      obError(line, "incompatible types in expression");
    }
    t = (t == typeReal || t2 == typeReal) ? typeReal
      : (t == typeSet && t2 == typeSet) ? typeSet
      : (isIntLike(t) && isIntLike(t2) && (t == typeLongint || t2 == typeLongint)) ? typeLongint : t;
  }
  return t;
}

static Type *parseTerm(void) {
  Type *t = parseFactor();
  while (sym == S_STAR || sym == S_SLASH || sym == S_DIV || sym == S_MOD || sym == S_AMP) {
    int op = sym; nextSym();
    Type *t2 = parseFactor();
    if (op == S_AMP) {
      if (t != typeBool || t2 != typeBool) obError(line, "& requires BOOLEAN");
      emit(OP_AND);
    } else if (op == S_STAR) {
      if (isIntLike(t) && isIntLike(t2) && (t == typeLongint || t2 == typeLongint)) emit(OP_LMUL);
      else if (t == typeInt && t2 == typeInt) emit(OP_IMUL);
      else if (t == typeReal && t2 == typeReal) emit(OP_FMUL);
      else if ((t == typeReal && t2 == typeInt) || (t == typeInt && t2 == typeReal)) {
        if (t == typeInt) emitI2FBelow(t); else emitI2FTop(t2);
        emit(OP_FMUL);
      }
      else if (t == typeSet && t2 == typeSet) emit(OP_SET_INTER);
      else obError(line, "bad operands for *");
      t = (t == typeReal || t2 == typeReal) ? typeReal
        : ((t == typeLongint || t2 == typeLongint) ? typeLongint : t);
    } else if (op == S_SLASH) {
      /* / is real division: INTEGER operands are converted implicitly (ext) */
      if (t == typeLongint || t2 == typeLongint) obError(line, "/ on LONGINT: convert to REAL explicitly");
      if (t != typeReal && t != typeInt) obError(line, "/ requires REAL operands");
      if (t2 != typeReal && t2 != typeInt) obError(line, "/ requires REAL operands");
      if (t == typeInt && t2 == typeInt) { emit(OP_I2F); emitI2FBelow(typeInt); }
      else if (t == typeInt) emitI2FBelow(t);
      else if (t2 == typeInt) emit(OP_I2F);
      emit(OP_FDIV);
      t = typeReal;
    } else {
      if (isIntLike(t) && isIntLike(t2) && (t == typeLongint || t2 == typeLongint)) {
        emit(op == S_DIV ? OP_LDIV : OP_LMOD);
        t = typeLongint;
      } else {
        if (t != typeInt || t2 != typeInt) obError(line, "DIV/MOD require INTEGER or LONGINT");
        emit(op == S_DIV ? OP_IDIV : OP_IMOD);
      }
    }
  }
  return t;
}

static int addString(const char *s) {
  Module *m = curMod;
  if (m->nstrings >= m->capstrings) {
    m->capstrings = m->capstrings * 2 + 8;
    m->strings = realloc(m->strings, m->capstrings * sizeof(char *));
  }
  m->strings[m->nstrings] = strdup(s);
  return m->nstrings++;
}

static Type *stringLitType(int len) {
  int dims[1] = {len + 1};
  Type *t = mkArrayType(typeChar, 1, dims);
  t->isStringLit = 1;
  return t;
}

static void parseCallArgs(Obj *proc, int mod);

static Type *parseFactor(void) {
  Type *t;
  switch (sym) {
    case S_INT:
      if (ival > INT32_MAX || ival < INT32_MIN) {
        emit(OP_CONST_L);
        bufU64(&curProc->code, (uint64_t)ival);
        nextSym();
        return typeLongint;
      }
      emit32(OP_CONST_I, (uint32_t)(int32_t)ival);
      nextSym();
      return typeInt;
    case S_REAL:
      emit(OP_CONST_R);
      bufU64(&curProc->code, (uint64_t)cellFromDouble(rval));
      nextSym();
      return typeReal;
    case S_CHAR:
      emit32(OP_CONST_I, (uint32_t)cval);
      nextSym();
      return typeChar;
    case S_STRING: {
      int idx = addString(sval);
      emit32(OP_CONST_S, (uint32_t)idx);
      nextSym();
      return stringLitType(slen);
    }
    case S_NIL:
      emit32(OP_CONST_I, 0);
      nextSym();
      return typeNil;
    case S_LBRACE: {
      /* set constructor */
      nextSym();
      emit32(OP_CONST_I, 0); /* accumulator */
      if (sym != S_RBRACE) {
        for (;;) {
          Type *t1 = parseSimpleExpr();
          if (t1 != typeInt && t1 != typeChar) obError(line, "set element must be INTEGER or CHAR");
          if (accept(S_DOTDOT)) {
            Type *t2 = parseSimpleExpr();
            if (t2 != typeInt && t2 != typeChar) obError(line, "set range bound must be INTEGER or CHAR");
            /* runtime loop: acc |= {lo..hi} */
            int tlo = allocTemp(), thi = allocTemp();
            emit32(OP_STORE_LOCAL, (uint32_t)thi); /* [acc, lo, hi] -> [acc, lo] */
            emit32(OP_STORE_LOCAL, (uint32_t)tlo); /* -> [acc] */
            int L = here();
            emit32(OP_LOAD_LOCAL, (uint32_t)tlo);
            emit32(OP_LOAD_LOCAL, (uint32_t)thi);
            emit(OP_ILE);
            int jz = emitJump(OP_JZ);
            emit(OP_DUP); /* acc */
            emit32(OP_LOAD_LOCAL, (uint32_t)tlo);
            emit32(OP_CONST_I, 1);
            emit(OP_SWAP);
            emit(OP_SHL);
            emit(OP_SET_UNION);
            emit32(OP_ADDR_LOCAL, (uint32_t)tlo);
            emit(OP_DUP); emit(OP_LOAD_AT);
            emit32(OP_CONST_I, 1); emit(OP_IADD); emit(OP_STORE_AT);
            int back = emitJump(OP_JMP);
            patch32(back, (uint32_t)L);
            patch32(jz, (uint32_t)here());
          } else {
            /* singleton: acc |= {e} : [acc, e] */
            emit32(OP_CONST_I, 1);
            emit(OP_SWAP);
            emit(OP_SHL);
            emit(OP_SET_UNION);
          }
          if (!accept(S_COMMA)) break;
        }
      }
      expect(S_RBRACE);
      return typeSet;
    }
    case S_LPAREN:
      nextSym();
      t = parseExpression();
      expect(S_RPAREN);
      return t;
    case S_TILDE: {
      nextSym();
      t = parseFactor();
      if (t != typeBool) obError(line, "~ requires BOOLEAN");
      emit(OP_NOT);
      return typeBool;
    }
    case S_IDENT: {
      int mod;
      Obj *o = readFirstIdent(&mod);
      if (o->modId == -1) {
        /* predefined function-like */
        switch (o->builtinId) {
          case PD_ABS: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t == typeInt) emit(OP_IABS);
            else if (t == typeLongint) emit(OP_LABS);
            else if (t == typeReal) emit(OP_FABS);
            else obError(line, "ABS requires number");
            return t;
          }
          case PD_ODD: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t == typeLongint) emit(OP_LODD);
            else if (t == typeInt) emit(OP_IODD);
            else obError(line, "ODD requires INTEGER or LONGINT");
            return typeBool;
          }
          case PD_LEN: {
            expect(S_LPAREN);
            Obj *a; int m2;
            a = readFirstIdent(&m2);
            t = parseDesignator(M_VAL, a, m2);
            if (t->kind == TK_POINTER && t->to && t->to->kind == TK_ARRAY) t = t->to;
            if (t->kind != TK_ARRAY) obError(line, "LEN requires array");
            int dim = 0;
            if (accept(S_COMMA)) {
              Type *dt; Cell dv = parseConstExpr(&dt);
              if (dt != typeInt || dv < 0 || dv >= t->ndim) obError(line, "bad LEN dimension");
              dim = (int)dv;
            }
            expect(S_RPAREN);
            emit32(OP_LEN, (uint32_t)dim);
            return typeInt;
          }
          case PD_ORD: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeChar) obError(line, "ORD requires CHAR");
            return typeInt;
          }
          case PD_CHR: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeInt) obError(line, "CHR requires INTEGER");
            return typeChar;
          }
          case PD_ENTIER: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeReal) obError(line, "ENTIER requires REAL");
            emit(OP_F2I);
            return typeInt;
          }
          case PD_FLOOR: {
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeReal) obError(line, "FLOOR requires REAL");
            emit(OP_FFLOOR);
            return typeInt;
          }
          case PD_PROCV: { /* LONGINT cell -> procedure value (identity, ext) */
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeLongint) obError(line, "PROCV requires LONGINT");
            return typeProc0;
          }
          case PD_PROCC: { /* procedure value -> LONGINT cell (identity, ext) */
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (!t || t->kind != TK_PROC) obError(line, "PROCC requires a procedure value");
            return typeLongint;
          }
          case PD_CAP: { /* CAP(ch): uppercase; expanded inline with existing opcodes */
            expect(S_LPAREN);
            t = parseExpression();
            expect(S_RPAREN);
            if (t != typeChar) obError(line, "CAP requires CHAR");
            int tmp = allocTemp();
            emit32(OP_STORE_LOCAL, (uint32_t)tmp);
            emit32(OP_LOAD_LOCAL, (uint32_t)tmp);
            emit32(OP_CONST_I, (uint32_t)'a');
            emit(OP_IGE);                       /* c >= 'a' */
            emit32(OP_LOAD_LOCAL, (uint32_t)tmp);
            emit32(OP_CONST_I, (uint32_t)'z');
            emit(OP_ILE);                       /* c <= 'z' */
            emit(OP_AND);
            int jz = emitJump(OP_JZ);
            emit32(OP_LOAD_LOCAL, (uint32_t)tmp);
            emit32(OP_CONST_I, 32);
            emit(OP_ISUB);
            int jm = emitJump(OP_JMP);
            patch32(jz, (uint32_t)here());
            emit32(OP_LOAD_LOCAL, (uint32_t)tmp);
            patch32(jm, (uint32_t)here());
            return typeChar;
          }
          default:
            obError(line, "'%s' cannot be used in an expression", o->name);
        }
      }
      if (o->cls == CL_PROC) {
        /* function procedure call in expression */
        if (!o->type) obError(line, "'%s' is not a function", o->name);
        if (sym == S_LPAREN) parseCallArgs(o, mod);
        else if (o->nparams == 0) emitCall(o, mod);
        else obError(line, "expected '(' in call to '%s'", o->name);
        return o->type;
      }
      if (o->cls == CL_VAR && o->type && o->type->kind == TK_PROC && sym == S_LPAREN) {
        /* indirect call through a procedure variable in an expression: f(args) (ext) */
        Type *pt = o->type;
        parseArgsList(pt->params, o->name);
        parseDesignator(M_VAL, o, mod); /* proc value on top of the args */
        emit(OP_CALLP);
        if (!pt->result) obError(line, "'%s' is a procedure variable without result", o->name);
        return pt->result;
      }
      t = parseDesignator(M_VAL, o, mod);
      /* type guard: designator(Type) */
      if (sym == S_LPAREN) {
        nextSym();
        Type *rt = parseQualType();
        expect(S_RPAREN);
        Type *rec = (rt->kind == TK_POINTER) ? rt->to : rt;
        if (t->kind != TK_POINTER || rec->kind != TK_RECORD) obError(line, "bad type guard");
        int m, ix; findTypeRef(rec, &m, &ix);
        emitTypeOp(OP_CHECKTYPE, m, ix);
        t = (rt->kind == TK_POINTER) ? rt : mkPointerType(rec);
      }
      return t;
    }
    default:
      obError(line, "expected factor, got %s", symName(sym));
  }
  return typeInt;
}

/* ---------- procedure calls ---------- */
static void emitCall(Obj *proc, int mod) {
  uint32_t steps = 0;
  if (mod != 255) steps = (uint32_t)(curLevel - proc->level);
  emit(OP_CALL);
  bufU32(&curProc->code, (uint32_t)mod);
  bufU32(&curProc->code, (uint32_t)proc->procIndex);
  bufU32(&curProc->code, steps);
}

/* structural match between a procedural type and a procedure object */
static int procSigMatches(Type *pt, Obj *proc) {
  if (!pt || pt->kind != TK_PROC) return 0;
  if (!proc || proc->cls != CL_PROC || proc->modId == -1) return 0;
  if (proc->nparams != pt->nparams) return 0;
  Obj *pa = pt->params, *pb = proc->params;
  while (pa && pb) {
    if (pa->isVarParam != pb->isVarParam) return 0;
    if (!typeEquals(pa->type, pb->type)) return 0;
    pa = pa->nextParam; pb = pb->nextParam;
  }
  if (pa || pb) return 0;
  if ((pt->result == NULL) != (proc->type == NULL)) return 0;
  if (pt->result && !typeEquals(pt->result, proc->type)) return 0;
  return 1;
}

/* Try to parse "Ident" or "Module.Ident" as a procedure reference and emit OP_PROCVAL.
   Returns 1 if consumed (proc value pushed), 0 with the lexer restored otherwise. */
static int tryEmitProcValue(Type *pt) {
  if (sym != S_IDENT) return 0;
  LexState ls;
  lexSave(&ls);
  int mod;
  Obj *o = readFirstIdent(&mod); /* obError (longjmp) on undefined ident: fine */
  /* a procedure identifier followed by '(' is a call, not a value; a 0-param function
     without '(' is called implicitly (dialect extension) -> not a value either */
  if (o->cls == CL_PROC && o->modId != -1 && sym != S_LPAREN &&
      !(o->nparams == 0 && o->type != NULL)) {
    if (!procSigMatches(pt, o))
      obError(line, "procedure '%s' does not match type '%s'", o->name, pt->name[0] ? pt->name : "?");
    emit(OP_PROCVAL);
    bufU32(&curProc->code, (uint32_t)mod);
    bufU32(&curProc->code, (uint32_t)o->procIndex);
    /* steps = slinks from current frame to the proc's defining frame.
       0xFFFFFFFF = module-level proc -> plain value; else snapshot (closure), steps may be 0. */
    uint32_t steps = (o->level == 0) ? 0xFFFFFFFFu : (uint32_t)(curLevel - o->level);
    bufU32(&curProc->code, steps);
    return 1;
  }
  lexRestore(&ls);
  return 0;
}

static void parseArgsList(Obj *params, const char *nm) {
  expect(S_LPAREN);
  Obj *p = params;
  if (sym != S_RPAREN) {
    for (;;) {
      if (!p) obError(line, "too many arguments in call to '%s'", nm);
      if (p->isVarParam) {
        int m2;
        Obj *a = readFirstIdent(&m2);
        if (a->cls != CL_VAR) obError(line, "VAR parameter needs a variable");
        Type *at = parseDesignator(
          (p->type->kind == TK_ARRAY) ? M_VARARG : M_ADDR, /* record VAR arg: payload addr (hdr applied) */
          a, m2);
        int ok = typeEquals(p->type, at) ||
                 (p->type->kind == TK_ARRAY && p->type->anyCharArray &&
                  at->kind == TK_ARRAY && at->elem->kind == TK_CHAR) ||
                 (p->type->kind == TK_ARRAY && p->type->anyCharArray &&
                  at->kind == TK_POINTER && at->to->kind == TK_ARRAY &&
                  at->to->elem->kind == TK_CHAR) ||
                 (p->type->kind == TK_ARRAY && p->type->isOpen &&
                  at->kind == TK_ARRAY && typeEquals(p->type->elem, at->elem)) ||
                 (p->type->kind == TK_ARRAY && p->type->isOpen &&
                  at->kind == TK_POINTER && at->to->kind == TK_ARRAY &&
                  typeEquals(p->type->elem, at->to->elem));
        if (!ok) obError(line, "VAR argument type mismatch in '%s'", nm);
      } else if (p->type->kind == TK_PROC && tryEmitProcValue(p->type)) {
        /* procedure value passed as actual argument */
      } else {
        if (p->type->kind == TK_RECORD)
          obError(line, "record value parameters not supported (use VAR) in '%s'", nm);
        Type *at = parseExpression();
        if (!typeAssignable(p->type, at)) obError(line, "argument type mismatch in '%s'", nm);
        if (p->type == typeReal && at == typeInt) emit(OP_I2F); /* implicit INTEGER -> REAL (ext) */
      }
      p = p->nextParam;
      if (!accept(S_COMMA)) break;
    }
  }
  expect(S_RPAREN);
  if (p) obError(line, "too few arguments in call to '%s'", nm);
}

static void parseCallArgs(Obj *proc, int mod) {
  parseArgsList(proc->params, proc->name);
  emitCall(proc, mod);
}

/* ---------- statements ---------- */
static void predefinedStatement(Obj *o) {
  switch (o->builtinId) {
    case PD_NEW: {
      expect(S_LPAREN);
      int m2; Obj *a = readFirstIdent(&m2);
      Type *t = parseDesignator(M_ADDR, a, m2);
      if (t->kind != TK_POINTER ||
          !(t->to->kind == TK_RECORD || (t->to->kind == TK_ARRAY && !t->to->isOpen)))
        obError(line, "NEW requires a pointer to record or to fixed array variable");
      int m, ix; findTypeRef(t, &m, &ix);
      emitTypeOp(OP_NEW, m, ix);
      emit(OP_STORE_AT);
      expect(S_RPAREN);
      return;
    }
    case PD_DISPOSE: {
      expect(S_LPAREN);
      int m2; Obj *a = readFirstIdent(&m2);
      if (a->cls != CL_VAR) obError(line, "DISPOSE needs a pointer variable");
      Type *t = parseDesignator(M_ADDR, a, m2);
      if (t->kind != TK_POINTER) obError(line, "DISPOSE requires a pointer variable");
      int m, ix; findTypeRef(t, &m, &ix);
      emitTypeOp(OP_DISPOSE, m, ix); /* pops slot addr, frees object, stores NIL */
      expect(S_RPAREN);
      return;
    }
    case PD_INC: case PD_DEC: {
      int delta = (o->builtinId == PD_INC) ? 1 : -1;
      expect(S_LPAREN);
      int m2; Obj *a = readFirstIdent(&m2);
      Type *t = parseDesignator(M_ADDR, a, m2);
      if (t != typeInt) obError(line, "INC/DEC require INTEGER variable");
      long long n = delta;
      if (accept(S_COMMA)) {
        Type *nt; Cell nv = parseConstExpr(&nt);
        if (nt != typeInt) obError(line, "INC/DEC amount must be INTEGER constant");
        n = delta * nv;
      }
      expect(S_RPAREN);
      /* stack: [addr]; DUP LOAD_AT + n STORE_AT */
      emit(OP_DUP);
      emit(OP_LOAD_AT);
      emit32(OP_CONST_I, (uint32_t)(int32_t)n);
      emit(OP_IADD);
      emit(OP_STORE_AT);
      return;
    }
    case PD_INCL: case PD_EXCL: {
      expect(S_LPAREN);
      int m2; Obj *a = readFirstIdent(&m2);
      Type *t = parseDesignator(M_ADDR, a, m2);
      if (t != typeSet) obError(line, "INCL/EXCL require SET variable");
      /* stack: [addr]; duplicate and load current set */
      emit(OP_DUP);             /* [addr, addr] */
      emit(OP_LOAD_AT);         /* [addr, set] */
      expect(S_COMMA);
      Type *et = parseExpression();
      if (et != typeInt) obError(line, "set element must be INTEGER");
      expect(S_RPAREN);
      /* stack: [addr, set, e] */
      emit32(OP_CONST_I, 1);    /* [addr, set, e, 1] */
      emit(OP_SWAP);            /* [addr, set, 1, e] */
      emit(OP_SHL);             /* [addr, set, mask] */
      emit(o->builtinId == PD_INCL ? OP_SET_UNION : OP_SET_DIFF);
      emit(OP_STORE_AT);        /* [ ] */
      return;
    }
    case PD_COPY: {
      expect(S_LPAREN);
      Type *t = parseExpression();
      if (t->kind != TK_ARRAY || t->elem->kind != TK_CHAR) obError(line, "COPY requires char arrays");
      expect(S_COMMA);
      Type *t2 = parseExpression();
      if (t2->kind != TK_ARRAY || t2->elem->kind != TK_CHAR) obError(line, "COPY requires char arrays");
      expect(S_RPAREN);
      emit(OP_COPY_STR);
      return;
    }
    default:
      obError(line, "'%s' is not a statement procedure here", o->name);
  }
}

static void parseStatement(void) {
  switch (sym) {
    case S_IDENT: {
      int mod;
      Obj *o = readFirstIdent(&mod);
      if (o->cls == CL_PROC) {
        if (o->modId == -1) {
          if (o->builtinId == PD_HALT) {
            /* HALT(n) -> builtin call */
            expect(S_LPAREN);
            Type *t = parseExpression();
            if (t != typeInt) obError(line, "HALT requires INTEGER");
            expect(S_RPAREN);
            emit(OP_CALL);
            bufU32(&curProc->code, 255);
            bufU32(&curProc->code, B_HALT);
            bufU32(&curProc->code, 0);
          } else {
            predefinedStatement(o);
          }
        } else {
          if (sym == S_LPAREN) parseCallArgs(o, mod);
          else if (o->nparams == 0) emitCall(o, mod);
          else obError(line, "expected '(' in call to '%s'", o->name);
        }
        return;
      }
      if (o->cls == CL_VAR && o->type && o->type->kind == TK_PROC && sym != S_ASSIGN) {
        /* indirect call through a procedure variable: f(args) (ext) */
        Type *pt = o->type;
        if (sym == S_LPAREN) {
          parseArgsList(pt->params, o->name);
          parseDesignator(M_VAL, o, mod); /* proc value on top of the args */
          emit(OP_CALLP);
        } else if (pt->nparams == 0) {
          parseDesignator(M_VAL, o, mod);
          emit(OP_CALLP);
        } else {
          obError(line, "expected '(' in call through '%s'", o->name);
        }
        if (pt->result) emit(OP_DROP); /* discard result of a function called as a statement */
        return;
      }
      if (o->cls != CL_VAR) obError(line, "expected variable, := or call");
      /* assignment */
      Type *lt = parseDesignator(M_ADDR, o, mod);
      if (sym != S_ASSIGN) obError(line, "expected := or (");
      nextSym();
      if (lt->kind == TK_ARRAY) {
        Type *rt = parseExpression();
        if (!(typeEquals(lt, rt) || (rt->isStringLit && lt->elem->kind == TK_CHAR)))
          obError(line, "array assignment type mismatch");
        /* lhs: payload addr already on stack; rhs: ref -> payload addr */
        emit(OP_TO_ADDR);
        emit32(OP_CONST_I, (uint32_t)(rt->ndim + 2));
        emit(OP_AADD);
        emit32(OP_COPY, (uint32_t)(rt->total * typeElemCells(rt->elem)));
      } else if (lt->kind == TK_RECORD) {
        Type *rt = parseExpression();
        if (rt->kind != TK_RECORD || !typeEquals(lt, rt)) obError(line, "record assignment type mismatch");
        emit32(OP_CONST_I, (uint32_t)gDesigHdr); /* rhs: skip heap header if any */
        emit(OP_AADD);
        emit32(OP_COPY, (uint32_t)lt->payload);
      } else if (lt->kind == TK_PROC) {
        /* f := ProcIdent | f := g (proc var) | f := NIL (ext) */
        if (!tryEmitProcValue(lt)) {
          Type *rt = parseExpression();
          if (!typeAssignable(lt, rt)) obError(line, "assignment type mismatch");
        }
        emit(OP_STORE_AT);
      } else {
        Type *rt = parseExpression();
        if (!typeAssignable(lt, rt)) obError(line, "assignment type mismatch");
        if (lt == typeReal && rt == typeInt) emit(OP_I2F); /* implicit INTEGER -> REAL (ext) */
        emit(OP_STORE_AT);
      }
      return;
    }
    case S_IF: {
      nextSym();
      int endJmps[64]; int nEnd = 0;
      int jz = 0;
      for (;;) {
        Type *t = parseExpression();
        if (t != typeBool) obError(line, "IF condition must be BOOLEAN");
        jz = emitJump(OP_JZ);
        expect(S_THEN);
        parseStatements();
        if (sym == S_ELSIF || sym == S_ELSE) {
          endJmps[nEnd++] = emitJump(OP_JMP);
          patch32(jz, (uint32_t)here());
          jz = -1;
        }
        if (sym == S_ELSIF) { nextSym(); continue; }
        if (sym == S_ELSE) { nextSym(); parseStatements(); }
        break;
      }
      if (jz >= 0) patch32(jz, (uint32_t)here());
      expect(S_END);
      for (int i = 0; i < nEnd; i++) patch32(endJmps[i], (uint32_t)here());
      return;
    }
    case S_WHILE: {
      /* Oberon-07: WHILE c1 DO S1 {ELSIF c2 DO S2} END — Dijkstra's guarded loop:
         each iteration runs the first true branch, then loops back to c1;
         the loop exits when every guard is false. */
      nextSym();
      int L = here();
      for (;;) {
        Type *t = parseExpression();
        if (t != typeBool) obError(line, "WHILE condition must be BOOLEAN");
        int jz = emitJump(OP_JZ);      /* -> next guard (or END) */
        expect(S_DO);
        parseStatements();
        int back = emitJump(OP_JMP);
        patch32(back, (uint32_t)L);    /* loop back to the first guard */
        patch32(jz, (uint32_t)here()); /* next guard, or END if none left */
        if (sym != S_ELSIF) break;
        nextSym();
      }
      expect(S_END);
      return;
    }
    case S_REPEAT: {
      nextSym();
      int L = here();
      parseStatements();
      expect(S_UNTIL);
      Type *t = parseExpression();
      if (t != typeBool) obError(line, "UNTIL condition must be BOOLEAN");
      int jz = emitJump(OP_JZ);
      patch32(jz, (uint32_t)L);
      return;
    }
    case S_FOR: {
      nextSym();
      char vn[64];
      readIdent(vn);
      Obj *vo = lookup(vn);
      if (!vo || vo->cls != CL_VAR || (!isIntLike(vo->type) && vo->type != typeChar)) obError(line, "FOR control variable must be INTEGER, LONGINT or CHAR variable");
      int isLong = (vo->type == typeLongint);
      expect(S_ASSIGN);
      parseDesignator(M_ADDR, vo, 0);
      Type *at = parseExpression();
      if (!isIntLike(at) && at != typeChar) obError(line, "FOR start must be INTEGER, LONGINT or CHAR");
      emit(OP_STORE_AT);
      expect(S_TO);
      int btemp = allocTemp();
      Type *bt = parseExpression();
      if (!isIntLike(bt) && bt != typeChar) obError(line, "FOR end must be INTEGER, LONGINT or CHAR");
      emit32(OP_STORE_LOCAL, (uint32_t)btemp);
      long long by = 1;
      if (accept(S_BY)) {
        Type *ct; Cell cv = parseConstExpr(&ct);
        if (!isIntLike(ct) || cv == 0) obError(line, "FOR BY must be a nonzero INTEGER/LONGINT constant");
        by = cv;
      }
      expect(S_DO);
      int L = here();
      /* cond: by>0 ? v<=b : v>=b */
      parseDesignator(M_VAL, vo, 0);
      emit32(OP_LOAD_LOCAL, (uint32_t)btemp);
      emit(by > 0 ? (isLong ? OP_LLE : OP_ILE) : (isLong ? OP_LGE : OP_IGE));
      int jz = emitJump(OP_JZ);
      parseStatements();
      /* v := v + by */
      parseDesignator(M_ADDR, vo, 0);
      emit(OP_DUP);
      emit(OP_LOAD_AT);
      if (isLong) { emit(OP_CONST_L); bufU64(&curProc->code, (uint64_t)(int64_t)by); }
      else emit32(OP_CONST_I, (uint32_t)(int32_t)by);
      emit(isLong ? OP_LADD : OP_IADD);
      emit(OP_STORE_AT);
      int back = emitJump(OP_JMP);
      patch32(back, (uint32_t)L);
      patch32(jz, (uint32_t)here());
      expect(S_END);
      return;
    }
    case S_CASE: {
      nextSym();
      /* peek: if the selector is a plain variable, remember it to narrow its
         static type inside each type-CASE branch (as Wirth's compiler does) */
      Obj *selObj = NULL;
      {
        LexState ls;
        lexSave(&ls);
        int m2;
        Obj *a = readFirstIdent(&m2);
        if (a && a->cls == CL_VAR && sym == S_OF) selObj = a;
        lexRestore(&ls);
      }
      Type *xt = parseExpression();
      if (xt->kind == TK_POINTER && xt->to && xt->to->kind == TK_RECORD) {
        /* Oberon-07 type CASE: CASE p OF T1, T2: S1 | T3: S2 ELSE S3 END.
           Runtime: p IS Tj in order (walks the extension chain); inside a
           branch p is statically of the label's type and runtime-checked. */
        int xtemp = allocTemp();
        emit32(OP_STORE_LOCAL, (uint32_t)xtemp); /* temp = selector */
        expect(S_OF);
        int endJmps[128]; int nEnd = 0;
        int pendFail[512]; int nPend = 0; /* label-false jumps awaiting the next branch */
        while (sym != S_ELSE && sym != S_END) {
          for (int i = 0; i < nPend; i++) patch32(pendFail[i], (uint32_t)here());
          nPend = 0;
          int bodyJmps[16]; int nBody = 0;
          int m0 = 0, ix0 = 0; Type *rt0 = NULL;
          int lastJz = -1;
          for (;;) { /* type labels of this branch */
            Type *rt = parseQualType();
            Type *rec = (rt->kind == TK_POINTER) ? rt->to : rt;
            if (rec->kind != TK_RECORD) obError(line, "type CASE label must be a record type");
            int m, ix;
            findTypeRef(rec, &m, &ix);
            if (!rt0) { rt0 = rt; m0 = m; ix0 = ix; }
            emit32(OP_LOAD_LOCAL, (uint32_t)xtemp);
            emitTypeOp(OP_ISTYPE, m, ix);
            int jz = emitJump(OP_JZ);
            if (nBody >= 16) obError(line, "too many labels in one CASE branch");
            bodyJmps[nBody++] = emitJump(OP_JMP);
            if (lastJz >= 0) patch32(lastJz, (uint32_t)here()); /* prev label false -> this label */
            lastJz = jz;
            if (!accept(S_COMMA)) break;
          }
          expect(S_COLON);
          if (nPend >= 512) obError(line, "too many CASE branches");
          pendFail[nPend++] = lastJz; /* all labels false -> next branch */
          int bodyPos = here();
          for (int i = 0; i < nBody; i++) patch32(bodyJmps[i], (uint32_t)bodyPos);
          /* runtime narrowing of the selector slot (check + keep ref) */
          emit32(OP_LOAD_LOCAL, (uint32_t)xtemp);
          emitTypeOp(OP_CHECKTYPE, m0, ix0);
          emit32(OP_STORE_LOCAL, (uint32_t)xtemp);
          /* static narrowing when the selector is a plain variable */
          Type *saved = NULL;
          if (selObj) { saved = selObj->type; selObj->type = rt0; }
          parseStatements();
          if (selObj) selObj->type = saved;
          if (nEnd >= 128) obError(line, "too many CASE branches");
          endJmps[nEnd++] = emitJump(OP_JMP);
          if (!accept(S_PIPE)) break;
        }
        if (accept(S_ELSE)) {
          for (int i = 0; i < nPend; i++) patch32(pendFail[i], (uint32_t)here());
          nPend = 0;
          parseStatements();
          endJmps[nEnd++] = emitJump(OP_JMP);
        }
        expect(S_END);
        int after = here();
        for (int i = 0; i < nPend; i++) patch32(pendFail[i], (uint32_t)after);
        for (int i = 0; i < nEnd; i++) patch32(endJmps[i], (uint32_t)after);
        return;
      }
      if (xt != typeInt && xt != typeChar) obError(line, "CASE expression must be INTEGER or CHAR");
      int xtemp = allocTemp();
      emit32(OP_STORE_LOCAL, (uint32_t)xtemp); /* temp = selector */
      int dispatchJmp = emitJump(OP_JMP);       /* -> dispatch code, emitted after all branch bodies */
      int endJmps[128]; int nEnd = 0;
      int bodyStart[128];
      int labLo[512], labHi[512], labBr[512]; int nLab = 0;
      int rangeTooBig = 0;
      expect(S_OF);
      int nb = 0;
      while (sym != S_ELSE && sym != S_END) {
        for (;;) { /* collect this branch's labels (they emit no code) */
          Type *lt; Cell lo = parseConstExpr(&lt);
          Cell hi = lo;
          if (accept(S_DOTDOT)) { Type *ht; hi = parseConstExpr(&ht); }
          if (hi < lo) obError(line, "bad case range");
          if (nLab >= 512) obError(line, "too many case labels");
          labLo[nLab] = (int)lo; labHi[nLab] = (int)hi; labBr[nLab] = nb; nLab++;
          if (hi - lo > 64) rangeTooBig = 1;
          if (!accept(S_COMMA)) break;
        }
        expect(S_COLON);
        bodyStart[nb] = here();
        parseStatements();
        endJmps[nEnd++] = emitJump(OP_JMP);
        nb++;
        if (nb >= 128) obError(line, "too many case branches");
        if (!accept(S_PIPE)) break;
      }
      int elseStart = -1;
      if (accept(S_ELSE)) { elseStart = here(); parseStatements(); endJmps[nEnd++] = emitJump(OP_JMP); }
      expect(S_END);
      /* ---- dispatch code (after the bodies; dispatchJmp lands here) ---- */
      patch32(dispatchJmp, (uint32_t)here());
      int useTable = !rangeTooBig && nLab >= 8;
      int mn = 0, mx = 0, tsize = 0;
      if (useTable) {
        mn = labLo[0]; mx = labHi[0];
        for (int i = 1; i < nLab; i++) { if (labLo[i] < mn) mn = labLo[i]; if (labHi[i] > mx) mx = labHi[i]; }
        tsize = mx - mn + 1;
        if (tsize > 1024 || tsize < 8) useTable = 0;
      }
      emit32(OP_LOAD_LOCAL, (uint32_t)xtemp);
      int defPos = 0;
      int tgtPos[1024];
      if (useTable) {
        emit(OP_JUMPTABLE);
        bufU32(&curProc->code, (uint32_t)tsize);
        bufU32(&curProc->code, (uint32_t)mn);
        defPos = here(); bufU32(&curProc->code, 0); /* default target, patched below */
        int tgt[1024];
        for (int i = 0; i < tsize; i++) tgt[i] = -1;
        for (int i = 0; i < nLab; i++)
          for (int v = labLo[i]; v <= labHi[i]; v++) tgt[v - mn] = bodyStart[labBr[i]];
        for (int i = 0; i < tsize; i++) { tgtPos[i] = here(); bufU32(&curProc->code, (uint32_t)(tgt[i] >= 0 ? tgt[i] : 0)); }
        int after0 = here();
        int defTarget0 = 0; /* patched below; keep positions */
        /* store for patching: reuse arrays — patch after computing `after` */
        (void)after0; (void)defTarget0;
        /* remember tgt entries that were gaps */
        for (int i = 0; i < tsize; i++) if (tgt[i] < 0) tgtPos[i] = -tgtPos[i] - 1; /* mark gap */
        /* stash tsize */
        useTable = -tsize; /* negative = table mode, |useTable| = tsize */
      } else {
        /* linear compare chain (JNZ -> body on first match) */
        for (int i = 0; i < nLab; i++) {
          emit32(OP_LOAD_LOCAL, (uint32_t)xtemp);
          emit32(OP_CONST_I, (uint32_t)labLo[i]);
          emit(OP_IGE);
          emit32(OP_LOAD_LOCAL, (uint32_t)xtemp);
          emit32(OP_CONST_I, (uint32_t)labHi[i]);
          emit(OP_ILE);
          emit(OP_AND);
          int jnz = emitJump(OP_JNZ);
          patch32(jnz, (uint32_t)bodyStart[labBr[i]]);
        }
        defPos = emitJump(OP_JMP); /* no match -> default */
      }
      int after = here();
      for (int i = 0; i < nEnd; i++) patch32(endJmps[i], (uint32_t)after);
      int defTarget = (elseStart >= 0) ? elseStart : after;
      if (useTable < 0) {
        int ts = -useTable;
        patch32(defPos, (uint32_t)defTarget);
        for (int i = 0; i < ts; i++)
          if (tgtPos[i] < 0) patch32(-tgtPos[i] - 1, (uint32_t)defTarget);
      } else {
        patch32(defPos, (uint32_t)defTarget);
      }
      return;
    }
    case S_WITH: {
      /* WITH p: T, q: U DO stmts END — p is statically POINTER TO T inside the body,
         with a runtime type check (OP_CHECKTYPE) at entry */
      nextSym();
      int shBase = nWithShadows;
      for (;;) {
        int m2; Obj *v = readFirstIdent(&m2);
        if (!v || v->cls != CL_VAR) obError(line, "WITH guard needs a pointer variable");
        if (v->type->kind != TK_POINTER || !v->type->to || v->type->to->kind != TK_RECORD)
          obError(line, "WITH guard variable must be a pointer to record");
        expect(S_COLON);
        Type *rt = parseQualType();
        Type *rec = (rt->kind == TK_POINTER) ? rt->to : rt;
        if (rec->kind != TK_RECORD) obError(line, "WITH guard type must be a record type");
        /* guard type must be the pointee or an extension of it (walk rec's base chain) */
        int ok = 0;
        for (Type *r = rec; r; r = (r->kind == TK_RECORD) ? r->base : NULL) if (r == v->type->to) { ok = 1; break; }
        if (!ok) obError(line, "WITH guard type must be the pointee or an extension of it");
        /* runtime check: push ref, CHECKTYPE, drop */
        parseDesignator(M_VAL, v, m2);
        int m, ix; findTypeRef(rec, &m, &ix);
        emitTypeOp(OP_CHECKTYPE, m, ix);
        emit(OP_DROP);
        /* shadow the variable with POINTER TO rec for the body (same storage) */
        Obj *sh = newObj(v->name, CL_VAR);
        sh->type = mkPointerType(rec);
        sh->level = v->level;
        sh->offset = v->offset;
        sh->isVarParam = v->isVarParam;
        sh->next = scopeStack[scopeTop];
        scopeStack[scopeTop] = sh;
        if (nWithShadows < 64) withShadows[nWithShadows++] = sh;
        if (!accept(S_COMMA)) break;
      }
      expect(S_DO);
      parseStatements();
      expect(S_END);
      while (nWithShadows > shBase) scopeStack[scopeTop] = withShadows[--nWithShadows]->next;
      return;
    }
    case S_RETURN:
      nextSym();
      if (curProc->hasResult) {
        if (curProc->result->kind == TK_PROC && tryEmitProcValue(curProc->result)) {
          /* RETURN ProcIdent : return a procedure value (possibly a closure) */
        } else {
          Type *t = parseExpression();
          if (!typeAssignable(curProc->result, t)) obError(line, "RETURN type mismatch");
          if (curProc->result == typeReal && t == typeInt) emit(OP_I2F); /* implicit INTEGER -> REAL (ext) */
        }
      } else if (sym != S_SEMI && !isEndSym()) {
        obError(line, "RETURN takes no expression in a plain procedure");
      }
      emit(OP_RET);
      return;
    default:
      return; /* empty statement */
  }
}

static int isEndSym(void) {
  return sym == S_END || sym == S_ELSE || sym == S_ELSIF || sym == S_UNTIL ||
         sym == S_PIPE || sym == S_EOF;
}

static void parseStatements(void) {
  if (!isEndSym()) parseStatement();
  while (accept(S_SEMI)) {
    if (isEndSym()) break;
    parseStatement();
  }
}

/* ---------- module ---------- */
Module *compileSource(FILE *f, const char *srcName, const char *dir) {
  lexInit(f, srcName);
  curMod = calloc(1, sizeof(Module));
  curProc = NULL;
  scopeTop = -1;
  nImpCache = 0;
  scopePush();
  installPredefined();
  scopePush();
  makeBuiltinModules();
  curLevel = 0;
  nextSym();
  expect(S_MODULE);
  readIdent(curMod->name);
  expect(S_SEMI);
  if (sym == S_IMPORT) { nextSym(); parseImports(dir); }
  /* module body is always proc index 0 */
  int bodyIdx = curMod->nprocs;
  addProc("<body>", 0, 1);
  parseDeclarations(1);
  curProc = &curMod->procs[bodyIdx];
  curLevel = 0;
  scopePush();
  if (accept(S_BEGIN)) parseStatements();
  emit(OP_RET);
  expect(S_END);
  if (sym == S_IDENT) {
    if (strcmp(name, curMod->name) != 0) obError(line, "module name mismatch at END");
    nextSym();
  }
  expect(S_DOT);
  scopePop();
  scopePop();
  return curMod;
}

int compileFile(const char *srcPath, const char *obcPath, const char *dir) {
  FILE *f = fopen(srcPath, "r");
  if (!f) { fprintf(stderr, "cannot open %s\n", srcPath); return 0; }
  if (setjmp(obJmp)) { fclose(f); return 0; }
  Module *m = compileSource(f, srcPath, dir);
  fclose(f);
  FILE *o = fopen(obcPath, "wb");
  if (!o) { fprintf(stderr, "cannot write %s\n", obcPath); return 0; }
  writeModule(m, o);
  fclose(o);
  return 1;
}
