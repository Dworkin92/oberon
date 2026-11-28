#include "module.h"
#include <ctype.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

/* ---------- install layout: OBERON_HOME / OBERON_PATH ----------
 *
 * Module search order (first match wins, so OBERON_PATH can override):
 *   1. dir of the current .Mod/.obc file (D)
 *   2. D/../lib, D/../../lib            (legacy project layout)
 *   3. OBERON_PATH entries, built as: "." (CWD) first, then the env var
 *      entries in order (separator ';' on Windows, ':' on POSIX),
 *      then $OBERON_HOME/lib appended if not already present.
 * OBERON_HOME defaults to the directory of the running executable with a
 * trailing /bin (or \bin) stripped.
 */

int obExePath(char *buf, int cap) {
#ifdef _WIN32
  return GetModuleFileNameA(NULL, buf, (DWORD)cap) > 0;
#else
  ssize_t n = readlink("/proc/self/exe", buf, (size_t)cap - 1);
  if (n <= 0) return 0;
  buf[n] = 0;
  return 1;
#endif
}

void obOberonHome(char *buf, int cap) {
  const char *h = getenv("OBERON_HOME");
  if (h && h[0]) { snprintf(buf, (size_t)cap, "%s", h); return; }
  char exe[600];
  if (obExePath(exe, sizeof exe)) {
    char *sep = strrchr(exe, '/');
    char *bs = strrchr(exe, '\\');
    if (bs && bs > sep) sep = bs;
    if (sep) *sep = 0; else snprintf(exe, sizeof exe, ".");
    size_t n = strlen(exe);
    if (n >= 4 && (exe[n-4] == '/' || exe[n-4] == '\\') &&
        tolower((unsigned char)exe[n-3]) == 'b' &&
        tolower((unsigned char)exe[n-2]) == 'i' &&
        tolower((unsigned char)exe[n-1]) == 'n')
      exe[n-4] = 0; /* strip trailing /bin */
    snprintf(buf, (size_t)cap, "%s", exe);
  } else {
    snprintf(buf, (size_t)cap, ".");
  }
}

int obSearchDirs(const char *fromDir, char dirs[][600], int maxDirs) {
  int n = 0;
#define ADDD(d) do { if (n < maxDirs) snprintf(dirs[n++], 600, "%s", (d)); } while (0)
  char b[600];
  ADDD(fromDir);
  snprintf(b, sizeof b, "%s/../lib", fromDir); ADDD(b);
  snprintf(b, sizeof b, "%s/../../lib", fromDir); ADDD(b);
  snprintf(b, sizeof b, "%s/../../selfhost", fromDir); ADDD(b);
  /* OBERON_PATH: "." (CWD) en tete */
  ADDD(".");
  char home[600], libdir[600];
  obOberonHome(home, sizeof home);
  snprintf(libdir, sizeof libdir, "%s/lib", home);
  int haveLib = 0;
  const char *pth = getenv("OBERON_PATH");
  if (pth && pth[0]) {
#ifdef _WIN32
    const char *sep = ";";   /* ':' existe dans les lettres de lecteur Windows */
#else
    const char *sep = ":";
#endif
    char tmp[2048];
    snprintf(tmp, sizeof tmp, "%s", pth);
    char *save = NULL;
    for (char *tok = strtok_r(tmp, sep, &save); tok; tok = strtok_r(NULL, sep, &save)) {
      if (!tok[0]) continue;      /* entree vide = CWD, deja ajoute via "." */
      ADDD(tok);
      if (strcmp(tok, libdir) == 0) haveLib = 1;
    }
  }
  if (!haveLib) ADDD(libdir);
#undef ADDD
  return n;
}

/* ---------- write ---------- */

void wU8(FILE *f, int v) { fputc(v & 0xFF, f); }
void wU32(FILE *f, uint32_t v) {
  fputc(v & 0xFF, f); fputc((v >> 8) & 0xFF, f);
  fputc((v >> 16) & 0xFF, f); fputc((v >> 24) & 0xFF, f);
}
void wU64(FILE *f, uint64_t v) {
  for (int i = 0; i < 8; i++) fputc((int)(v >> (8 * i)) & 0xFF, f);
}
void wStr(FILE *f, const char *s) {
  int n = (int)strlen(s);
  wU32(f, (uint32_t)n);
  fwrite(s, 1, n, f);
}

static void writeType(Module *m, FILE *f, TypeDef *td) {
  Type *t = td->t;
  wU8(f, t->kind);
  wStr(f, t->name);
  wU8(f, td->exported);
  switch (t->kind) {
    case TK_ARRAY:
      if (t->isOpen) wU32(f, 0xFFFFFFFFu); /* sentinel: open array param, no dims stored */
      else {
        wU32(f, t->ndim);
        for (int i = 0; i < t->ndim; i++) wU32(f, t->dims[i]);
      }
      wU32(f, typeIndex(m, t->elem));
      break;
    case TK_RECORD: {
      wU32(f, t->payload);
      wU32(f, t->base ? (uint32_t)typeIndex(m, t->base) : 0xFFFFFFFFu);
      int nf = 0;
      for (Field *fl = t->fields; fl; fl = fl->next) nf++;
      wU32(f, nf);
      for (Field *fl = t->fields; fl; fl = fl->next) {
        wStr(f, fl->name);
        wU32(f, typeIndex(m, fl->type));
        wU32(f, fl->offset);
      }
      break;
    }
    case TK_POINTER:
      wU32(f, typeIndex(m, t->to));
      break;
    case TK_PROC: {
      wU32(f, (uint32_t)t->nparams);
      for (Obj *pa = t->params; pa; pa = pa->nextParam) {
        wU32(f, typeIndex(m, pa->type));
        wU8(f, pa->isVarParam);
      }
      wU32(f, t->result ? (uint32_t)typeIndex(m, t->result) : 0xFFFFFFFFu);
      break;
    }
    default:
      break;
  }
}

void registerTypeDeep(Module *m, Type *t) {
  if (!t || t->visited == gTypeStamp) return;
  t->visited = gTypeStamp;
  typeIndex(m, t);
  switch (t->kind) {
    case TK_ARRAY: registerTypeDeep(m, t->elem); break;
    case TK_RECORD:
      registerTypeDeep(m, t->base);
      for (Field *fl = t->fields; fl; fl = fl->next) registerTypeDeep(m, fl->type);
      break;
    case TK_POINTER: registerTypeDeep(m, t->to); break;
    case TK_PROC:
      for (Obj *pa = t->params; pa; pa = pa->nextParam) registerTypeDeep(m, pa->type);
      registerTypeDeep(m, t->result);
      break;
    default: break;
  }
}

void writeModule(Module *m, FILE *f) {
  /* register every reachable type first so the count is correct;
     fresh stamp so types shared with a previously compiled module
     (basic types, imported types) are re-registered for THIS module */
  gTypeStamp++;
  for (Obj *o = m->globals; o; o = o->nextGlobal) registerTypeDeep(m, o->type);
  for (int i = 0; i < m->nprocs; i++) {
    Proc *p = &m->procs[i];
    for (int j = 0; j < p->nparams; j++) registerTypeDeep(m, p->params[j]->type);
    registerTypeDeep(m, p->result);
  }
  fwrite("OBC7", 1, 4, f);
  wU32(f, 1); /* version */
  wStr(f, m->name);
  wU32(f, m->nimports);
  for (int i = 0; i < m->nimports; i++) wStr(f, m->imports[i]);
  wU32(f, m->globalSize);
  int ng = 0;
  for (Obj *o = m->globals; o; o = o->nextGlobal) ng++;
  wU32(f, ng);
  for (Obj *o = m->globals; o; o = o->nextGlobal) {
    wStr(f, o->name);
    wU32(f, o->offset);
    wU32(f, typeIndex(m, o->type));
    wU8(f, o->exported);
  }
  wU32(f, m->ntypes);
  for (int i = 0; i < m->ntypes; i++) writeType(m, f, &m->types[i]);
  wU32(f, m->nprocs);
  for (int i = 0; i < m->nprocs; i++) {
    Proc *p = &m->procs[i];
    wStr(f, p->name);
    wU8(f, p->exported);
    wU8(f, p->isBody);
    wU32(f, p->nparams);
    for (int j = 0; j < p->nparams; j++) {
      Obj *pa = p->params[j];
      wStr(f, pa->name);
      wU32(f, typeIndex(m, pa->type));
      wU8(f, pa->isVarParam);
    }
    wU32(f, p->nlocals);
    wU8(f, p->hasResult);
    wU32(f, p->hasResult ? typeIndex(m, p->result) : 0xFFFFFFFFu);
    wU32(f, p->code.len);
    fwrite(p->code.b, 1, p->code.len, f);
  }
  wU32(f, m->nstrings);
  for (int i = 0; i < m->nstrings; i++) wStr(f, m->strings[i]);
  /* consts section (appended at the end; old readers stop after strings) */
  int nc = 0;
  for (Obj *o = m->consts; o; o = o->nextConst) nc++;
  wU32(f, (uint32_t)nc);
  for (Obj *o = m->consts; o; o = o->nextConst) {
    wStr(f, o->name);
    wU32(f, (uint32_t)typeIndex(m, o->type));
    wU64(f, (uint64_t)o->cval);
    wU8(f, o->exported);
  }
}

/* ---------- read ---------- */

int rU8(FILE *f) { return fgetc(f); }
uint64_t rU64(FILE *f) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) v |= (uint64_t)fgetc(f) << (8 * i);
  return v;
}
uint32_t rU32(FILE *f) {
  int a = fgetc(f), b = fgetc(f), c = fgetc(f), d = fgetc(f);
  if (d == EOF) obError(obLine, "truncated .obc file");
  return (uint32_t)(a | (b << 8) | (c << 16) | ((uint32_t)d << 24));
}
char *rStr(FILE *f) {
  uint32_t n = rU32(f);
  char *s = malloc(n + 1);
  if (n && fread(s, 1, n, f) != n) obError(obLine, "truncated .obc string");
  s[n] = 0;
  return s;
}

/* resolve a raw type index stored as (Type*)(uintptr_t)idx */
static Type *resolveIdx(uintptr_t raw, Type **types, int nt) {
  if (raw == 0xFFFFFFFFu) return NULL;
  if (raw < (uintptr_t)nt) return types[raw];
  return typeNil;
}

/* find name.obc (runtime) or name.obc/name.Mod (compile, allowMod=1) in the
   search dirs built by obSearchDirs; first match wins */
int findModuleFile(const char *name, const char *dir, int allowMod, char *out, int outsz) {
  static char dirs[80][600];
  int n = obSearchDirs(dir, dirs, 80);
  for (int i = 0; i < n; i++) {
    char p[700];
    snprintf(p, sizeof p, "%s/%s.obc", dirs[i], name);
    FILE *f = fopen(p, "rb");
    if (f) { fclose(f); snprintf(out, (size_t)outsz, "%s", p); return 1; }
    if (allowMod) {
      snprintf(p, sizeof p, "%s/%s.Mod", dirs[i], name);
      f = fopen(p, "rb");
      if (f) { fclose(f); snprintf(out, (size_t)outsz, "%s", p); return 1; }
    }
  }
  return 0;
}

LoadedModule *loadModuleFile(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  char magic[4];
  if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "OBC7", 4) != 0) { fclose(f); return NULL; }
  if (rU32(f) != 1) { fclose(f); return NULL; }
  LoadedModule *lm = calloc(1, sizeof(LoadedModule));
  char *s = rStr(f); strncpy(lm->name, s, 63); free(s);
  int ni = (int)rU32(f);
  lm->imports = malloc(sizeof(char *) * (ni ? ni : 1));
  lm->nimports = ni;
  for (int i = 0; i < lm->nimports; i++) lm->imports[i] = rStr(f);
  lm->globalSize = (int)rU32(f);
  int ng = (int)rU32(f);
  for (int i = 0; i < ng; i++) {
    Obj *o = calloc(1, sizeof(Obj));
    s = rStr(f); strncpy(o->name, s, 63); free(s);
    o->offset = (int)rU32(f);
    uint32_t tidx = rU32(f);
    o->exported = rU8(f);
    o->cls = CL_VAR;
    o->type = (Type *)(uintptr_t)(tidx + 1); /* resolve after types are read */
    o->next = lm->exportedVars;
    lm->exportedVars = o;
  }
  int nt = (int)rU32(f);
  lm->ntypes = nt;
  lm->types = calloc(nt ? nt : 1, sizeof(Type *));
  for (int i = 0; i < nt; i++) {
    int k = rU8(f);
    char *tn = rStr(f);
    rU8(f); /* exported flag */
    Type *t;
    switch (k) {
      case TK_INT: t = typeInt; break;
      case TK_REAL: t = typeReal; break;
      case TK_BOOL: t = typeBool; break;
      case TK_CHAR: t = typeChar; break;
      case TK_SET: t = typeSet; break;
      case TK_NIL: t = typeNil; break;
      case TK_LONGINT: t = typeLongint; break;
      default: t = newType(k); break;
    }
    strncpy(t->name, tn, 63); free(tn);
    lm->types[i] = t;
    switch (k) {
      case TK_ARRAY: {
        int nd = (int)rU32(f);
        if (nd < 0) { /* 0xFFFFFFFF sentinel: open array (formal param ARRAY OF T) */
          t->isOpen = 1; t->ndim = 1; t->dims[0] = 0x3FFFFFFF; t->total = 0x3FFFFFFF;
        } else {
          t->ndim = nd; t->total = 1;
          for (int d = 0; d < nd; d++) { t->dims[d] = (int)rU32(f); t->total *= t->dims[d]; }
        }
        t->elem = (Type *)(uintptr_t)rU32(f);
        break;
      }
      case TK_RECORD: {
        t->payload = (int)rU32(f);
        uint32_t b = rU32(f);
        t->base = (Type *)(uintptr_t)b; /* resolve below */
        int nf = (int)rU32(f);
        Field **tail = &t->fields;
        for (int j = 0; j < nf; j++) {
          Field *fl = calloc(1, sizeof(Field));
          char *fn = rStr(f); strncpy(fl->name, fn, 63); free(fn);
          fl->type = (Type *)(uintptr_t)rU32(f);
          fl->offset = (int)rU32(f);
          *tail = fl; tail = &fl->next;
          t->nfields++;
        }
        break;
      }
      case TK_POINTER:
        t->to = (Type *)(uintptr_t)rU32(f);
        break;
      case TK_PROC: {
        int np = (int)rU32(f);
        t->nparams = np;
        Obj **tail = &t->params;
        for (int j = 0; j < np; j++) {
          Obj *pa = calloc(1, sizeof(Obj));
          uint32_t tidx = rU32(f);
          pa->isVarParam = rU8(f);
          pa->cls = CL_VAR;
          pa->type = (Type *)(uintptr_t)(tidx + 1); /* resolve below */
          *tail = pa; tail = &pa->nextParam;
        }
        uint32_t ridx = rU32(f);
        t->result = (Type *)(uintptr_t)(ridx != 0xFFFFFFFFu ? ridx + 1 : 0); /* resolve below */
        break;
      }
      default: break;
    }
  }
  /* fix cross references */
  for (int i = 0; i < nt; i++) {
    Type *t = lm->types[i];
    if (t->kind == TK_ARRAY) t->elem = resolveIdx((uintptr_t)t->elem, lm->types, nt);
    else if (t->kind == TK_POINTER) t->to = resolveIdx((uintptr_t)t->to, lm->types, nt);
    else if (t->kind == TK_RECORD) {
      t->base = resolveIdx((uintptr_t)t->base, lm->types, nt);
      for (Field *fl = t->fields; fl; fl = fl->next)
        fl->type = resolveIdx((uintptr_t)fl->type, lm->types, nt);
    }
    else if (t->kind == TK_PROC) {
      for (Obj *pa = t->params; pa; pa = pa->nextParam)
        pa->type = resolveIdx((uintptr_t)pa->type - 1, lm->types, nt);
      t->result = t->result ? resolveIdx((uintptr_t)t->result - 1, lm->types, nt) : NULL;
    }
  }
  for (Obj *o = lm->exportedVars; o; o = o->next)
    o->type = resolveIdx((uintptr_t)o->type - 1, lm->types, nt);

  int np = (int)rU32(f);
  lm->nprocs = np;
  lm->procs = calloc(np ? np : 1, sizeof(LProc));
  for (int i = 0; i < np; i++) {
    LProc *p = &lm->procs[i];
    s = rStr(f); strncpy(p->name, s, 63); free(s);
    p->exported = rU8(f);
    p->isBody = rU8(f);
    int npar = (int)rU32(f);
    p->nparams = npar;
    p->params = calloc(npar ? npar : 1, sizeof(Obj *));
    for (int j = 0; j < npar; j++) {
      Obj *pa = calloc(1, sizeof(Obj));
      s = rStr(f); strncpy(pa->name, s, 63); free(s);
      uint32_t tidx = rU32(f);
      pa->isVarParam = rU8(f);
      pa->cls = CL_VAR;
      pa->type = (Type *)(uintptr_t)(tidx + 1);
      p->params[j] = pa;
    }
    p->nlocals = (int)rU32(f);
    p->hasResult = rU8(f);
    uint32_t ridx = rU32(f);
    p->codelen = (int)rU32(f);
    p->code = malloc(p->codelen ? p->codelen : 1);
    if (p->codelen && fread(p->code, 1, p->codelen, f) != (size_t)p->codelen)
      obError(obLine, "truncated code in .obc");
    for (int j = 0; j < npar; j++)
      p->params[j]->type = resolveIdx((uintptr_t)p->params[j]->type - 1, lm->types, nt);
    p->result = (ridx != 0xFFFFFFFFu) ? resolveIdx(ridx, lm->types, nt) : NULL;
  }
  int ns = (int)rU32(f);
  lm->nstrings = ns;
  lm->strings = calloc(ns ? ns : 1, sizeof(char *));
  for (int i = 0; i < ns; i++) lm->strings[i] = rStr(f);
  /* consts section (optional, appended after strings; absent in old .obc) */
  int cbyte = fgetc(f);
  if (cbyte != EOF) {
    ungetc(cbyte, f);
    int nc = (int)rU32(f);
    for (int i = 0; i < nc; i++) {
      Obj *o = calloc(1, sizeof(Obj));
      s = rStr(f); strncpy(o->name, s, 63); free(s);
      uint32_t tidx = rU32(f);
      o->cval = (Cell)rU64(f);
      o->exported = rU8(f);
      o->cls = CL_CONST;
      o->type = (Type *)(uintptr_t)(tidx + 1); /* resolve after types are read */
      o->nextConst = lm->consts;
      lm->consts = o;
    }
    /* types are already read at this point (consts come after strings) */
    for (Obj *o = lm->consts; o; o = o->nextConst)
      o->type = resolveIdx((uintptr_t)o->type - 1, lm->types, lm->ntypes);
  }
  fclose(f);

  /* build members list of exported items for import resolution */
  Obj **tail = &lm->members;
  for (int i = 0; i < np; i++) {
    if (!lm->procs[i].exported) continue;
    Obj *o = newObj(lm->procs[i].name, CL_PROC);
    o->procIndex = i;
    o->nparams = lm->procs[i].nparams;
    o->type = lm->procs[i].result;
    Obj **pt = &o->params;
    for (int j = 0; j < lm->procs[i].nparams; j++) {
      Obj *src = lm->procs[i].params[j];
      Obj *cp = newObj(src->name, CL_VAR);
      cp->type = src->type;
      cp->isVarParam = src->isVarParam;
      *pt = cp; pt = &cp->nextParam;
    }
    *tail = o; tail = &o->next;
  }
  for (int i = 0; i < nt; i++) {
    Type *t = lm->types[i];
    if (t->kind == TK_INT || t->kind == TK_REAL || t->kind == TK_BOOL ||
        t->kind == TK_CHAR || t->kind == TK_SET || t->kind == TK_NIL ||
        t->kind == TK_UNDEF) continue;
    if (!t->name[0]) continue;
    Obj *o = newObj(t->name, CL_TYPE);
    o->type = t;
    *tail = o; tail = &o->next;
  }
  for (Obj *o = lm->exportedVars; o; o = o->next) {
    if (!o->exported) continue;
    Obj *cp = newObj(o->name, CL_VAR);
    cp->type = o->type;
    cp->offset = o->offset;
    cp->level = 0;
    *tail = cp; tail = &cp->next;
  }
  for (Obj *o = lm->consts; o; o = o->nextConst) {
    if (!o->exported) continue;
    Obj *cp = newObj(o->name, CL_CONST);
    cp->type = o->type;
    cp->cval = o->cval;
    *tail = cp; tail = &cp->next;
  }
  return lm;
}

Obj *moduleObjFromLoaded(LoadedModule *lm, int modId, int exportedOnly) {
  (void)exportedOnly;
  Obj *m = newObj(lm->name, CL_MODULE);
  m->modId = modId;
  m->members = lm->members;
  m->builtin = 0;
  return m;
}
