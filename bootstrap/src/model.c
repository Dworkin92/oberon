#include "model.h"

Type *typeInt, *typeReal, *typeBool, *typeChar, *typeSet, *typeNil, *typeLongint;
Type *typeProc0;
Type *typeCharArrayAny;
Type *typeAnyPointer;
int gTypeStamp = 1; /* never 0: fresh types have visited==0 and must not match the stamp at parse time */
Obj *scopeStack[64];
int scopeTop = -1;
Module *curMod;
Proc *curProc;

void initBasicTypes(void) {
  typeInt = newType(TK_INT); strcpy(typeInt->name, "INTEGER");
  typeReal = newType(TK_REAL); strcpy(typeReal->name, "REAL");
  typeBool = newType(TK_BOOL); strcpy(typeBool->name, "BOOLEAN");
  typeChar = newType(TK_CHAR); strcpy(typeChar->name, "CHAR");
  typeSet = newType(TK_SET); strcpy(typeSet->name, "SET");
  typeNil = newType(TK_NIL); strcpy(typeNil->name, "NIL");
  typeLongint = newType(TK_LONGINT); strcpy(typeLongint->name, "LONGINT");
  typeCharArrayAny = mkArrayType(typeChar, 1, (int[]){0x3FFFFFFF});
  typeCharArrayAny->anyCharArray = 1;
  typeAnyPointer = newType(TK_POINTER);
  strcpy(typeAnyPointer->name, "ANYPOINTER");
  typeAnyPointer->anyPointer = 1;
  typeProc0 = newType(TK_PROC); /* PROCEDURE() with no params/result: for PROCV/PROCC casts */
  strcpy(typeProc0->name, "PROCEDURE()");
}

Type *newType(int kind) {
  Type *t = calloc(1, sizeof(Type));
  t->kind = kind;
  return t;
}

int typeSizeCells(Type *t) {
  /* var slot size in cells: records occupy their payload inline, arrays are heap refs (1) */
  if (t && t->kind == TK_RECORD) return t->payload;
  return 1;
}

/* full inline size in cells when the type is stored inline (record field):
   arrays occupy their whole data area, records their payload */
int typeInlineCells(Type *t) {
  if (!t) return 1;
  if (t->kind == TK_RECORD) return t->payload;
  if (t->kind == TK_ARRAY && !t->isOpen) return t->total * typeElemCells(t->elem);
  return 1;
}

/* cells occupied by one array element (records are stored inline) */
int typeElemCells(Type *e) {
  if (e && e->kind == TK_RECORD) return e->payload;
  return 1;
}

static int procTypeEquals(Type *a, Type *b);

int typeEquals(Type *a, Type *b) {
  if (a == b) return 1;
  if (!a || !b) return 0;
  if (a->kind != b->kind) return 0;
  switch (a->kind) {
    case TK_ARRAY:
      return a->ndim == b->ndim && a->total == b->total && typeEquals(a->elem, b->elem) &&
             memcmp(a->dims, b->dims, sizeof(int) * a->ndim) == 0;
    case TK_POINTER:
      return typeEquals(a->to, b->to);
    case TK_PROC:
      return procTypeEquals(a, b);
    case TK_RECORD:
      return a == b; /* nominal for records */
    default:
      return 1; /* basic types are singletons */
  }
}

int typeAssignable(Type *dst, Type *src) {
  if (!dst || !src) return 0;
  if (typeEquals(dst, src)) return 1;
  if (dst->kind == TK_POINTER && src->kind == TK_NIL) return 1;
  if (dst->kind == TK_PROC && src->kind == TK_NIL) return 1; /* NIL assignable to proc var */
  /* INTEGER widens to LONGINT */
  if (dst->kind == TK_LONGINT && src->kind == TK_INT) return 1;
  /* INTEGER converts implicitly to REAL (ext) */
  if (dst->kind == TK_REAL && src->kind == TK_INT) return 1;
  /* string literal to ARRAY OF CHAR */
  if (dst->kind == TK_ARRAY && src->kind == TK_ARRAY && src->isStringLit &&
      dst->elem->kind == TK_CHAR && src->total <= dst->total) return 1;
  /* any char array accepted where the marker is expected */
  if (dst->kind == TK_ARRAY && dst->anyCharArray && src->kind == TK_ARRAY &&
      src->elem->kind == TK_CHAR) return 1;
  /* pointer to array of char accepted where the char-array marker is expected */
  if (dst->kind == TK_ARRAY && dst->anyCharArray && src->kind == TK_POINTER &&
      src->to && src->to->kind == TK_ARRAY && src->to->elem->kind == TK_CHAR) return 1;
  /* open array param (ARRAY OF T) accepts any array with the same element type */
  if (dst->kind == TK_ARRAY && dst->isOpen && src->kind == TK_ARRAY &&
      typeEquals(dst->elem, src->elem)) return 1;
  /* open array param also accepts a pointer to array of the same element type */
  if (dst->kind == TK_ARRAY && dst->isOpen && src->kind == TK_POINTER &&
      src->to && src->to->kind == TK_ARRAY && typeEquals(dst->elem, src->to->elem)) return 1;
  /* string literal to an open ARRAY OF CHAR param */
  if (dst->kind == TK_ARRAY && dst->isOpen && dst->elem->kind == TK_CHAR &&
      src->kind == TK_ARRAY && src->isStringLit) return 1;
  /* derived pointer assignable to base pointer (record extension) */
  if (dst->kind == TK_POINTER && src->kind == TK_POINTER &&
      dst->to->kind == TK_RECORD && src->to->kind == TK_RECORD) {
    for (Type *r = src->to; r; r = r->base)
      if (r == dst->to) return 1;
  }
  return 0;
}

Field *findField(Type *rec, const char *fname) {
  for (Type *r = rec; r; r = r->base) {
    for (Field *f = r->fields; f; f = f->next) {
      if (strcmp(f->name, fname) == 0) return f;
    }
  }
  return NULL;
}

int recordPayload(Type *rec) { return rec->payload; }

Obj *newObj(const char *nm, int cls) {
  Obj *o = calloc(1, sizeof(Obj));
  strncpy(o->name, nm, 63);
  o->cls = cls;
  return o;
}

void scopePush(void) {
  if (scopeTop >= 63) obError(obLine, "scope overflow");
  scopeStack[++scopeTop] = NULL;
}

void scopePop(void) {
  if (scopeTop < 0) obError(obLine, "scope underflow");
  scopeTop--;
}

void insertObj(Obj *o) {
  if (scopeTop < 0) obError(obLine, "no scope");
  if (lookupIn(scopeStack[scopeTop], o->name))
    obError(obLine, "duplicate identifier '%s'", o->name);
  o->next = scopeStack[scopeTop];
  scopeStack[scopeTop] = o;
}

Obj *lookupIn(Obj *list, const char *nm) {
  for (Obj *o = list; o; o = o->next)
    if (strcmp(o->name, nm) == 0) return o;
  return NULL;
}

Obj *lookup(const char *nm) {
  for (int i = scopeTop; i >= 0; i--) {
    Obj *o = lookupIn(scopeStack[i], nm);
    if (o) return o;
  }
  return NULL;
}

int typeIndex(Module *m, Type *t) {
  for (int i = 0; i < m->ntypes; i++)
    if (m->types[i].t == t) return i;
  if (m->ntypes >= m->captypes) {
    m->captypes = m->captypes * 2 + 8;
    m->types = realloc(m->types, m->captypes * sizeof(TypeDef));
  }
  m->types[m->ntypes].t = t;
  memcpy(m->types[m->ntypes].name, t->name, 64);
  m->types[m->ntypes].name[63] = 0;
  m->types[m->ntypes].exported = 0;
  m->types[m->ntypes].idx = m->ntypes;
  return m->ntypes++;
}

Type *mkArrayType(Type *elem, int ndim, int *dims) {
  Type *t = newType(TK_ARRAY);
  t->elem = elem;
  t->ndim = ndim;
  t->total = 1;
  for (int i = 0; i < ndim; i++) {
    if (dims[i] <= 0) obError(obLine, "array dimension must be positive");
    t->dims[i] = dims[i];
    t->total *= dims[i];
  }
  return t;
}

Type *mkOpenArrayType(Type *elem) {
  Type *t = mkArrayType(elem, 1, (int[]){0x3FFFFFFF});
  t->isOpen = 1;
  return t;
}

Type *mkPointerType(Type *to) {
  Type *t = newType(TK_POINTER);
  t->to = to;
  return t;
}

Type *mkProcType(void) { return newType(TK_PROC); }

/* structural equality of procedure types: same VAR-ness, param types and result */
static int procTypeEquals(Type *a, Type *b) {
  if (a->nparams != b->nparams) return 0;
  Obj *pa = a->params, *pb = b->params;
  while (pa && pb) {
    if (pa->isVarParam != pb->isVarParam) return 0;
    if (!typeEquals(pa->type, pb->type)) return 0;
    pa = pa->nextParam; pb = pb->nextParam;
  }
  if (pa || pb) return 0;
  if ((a->result == NULL) != (b->result == NULL)) return 0;
  if (a->result && !typeEquals(a->result, b->result)) return 0;
  return 1;
}

Type *mkRecordType(void) { return newType(TK_RECORD); }

void completeRecord(Type *rec, Type *base, Field *fields, int nfields) {
  rec->base = base;
  rec->fields = fields;
  rec->nfields = nfields;
  int payload = base ? base->payload : 0;
  for (Field *f = fields; f; f = f->next) {
    f->offset = payload;
    payload += typeInlineCells(f->type);
  }
  rec->payload = payload;
  rec->tag = ++curMod->tagCounter;
}
