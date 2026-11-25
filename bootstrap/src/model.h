#ifndef MODEL_H
#define MODEL_H

#include "ob.h"

/* Type kinds */
enum {
  TK_UNDEF = 0, TK_NIL, TK_INT, TK_REAL, TK_BOOL, TK_CHAR, TK_SET,
  TK_ARRAY, TK_RECORD, TK_POINTER, TK_LONGINT
};

typedef struct Type Type;
typedef struct Field {
  char name[64];
  Type *type;
  int offset; /* in cells, relative to record payload start */
  struct Field *next;
} Field;

struct Type {
  int kind;
  char name[64];   /* for named types */
  int isStringLit; /* array-of-char produced by a string literal */
  int anyCharArray; /* marker type: accepts any ARRAY OF CHAR (Out.String, In.Line) */
  int anyPointer;   /* marker type: accepts any POINTER (DISPOSE) */
  int isOpen;      /* open array: formal parameter "ARRAY OF T" (any length) */
  /* ARRAY */
  Type *elem;
  int ndim, dims[8], total; /* total = product of dims */
  /* RECORD */
  Type *base;      /* base record type or NULL */
  Field *fields;   /* own fields (not incl. base) */
  int nfields;
  int payload;     /* payload size in cells (incl. base fields) */
  int tag;         /* compile-time tag id (records) */
  /* POINTER */
  Type *to;
  int visited;     /* internal: stamp == gTypeStamp when registered for the current writeModule */
};

/* Object classes */
enum { CL_CONST, CL_VAR, CL_TYPE, CL_PROC, CL_MODULE };

typedef struct Obj {
  char name[64];
  int cls;
  Type *type;
  /* CL_CONST */
  Cell cval;
  /* CL_VAR */
  int level;        /* declaration level; globals are level 0 */
  int offset;       /* cell offset in locals frame or global segment */
  int modId;        /* 0 = own module, 1..n = import local id, for globals */
  int isVarParam;
  /* CL_PROC */
  int nparams;
  struct Obj *params;   /* linked list of param Objs (CL_VAR, isVarParam set) */
  int procIndex;        /* index in Module.procs */
  int exported;
  /* CL_MODULE */
  struct Obj *members;  /* linked list of exported members */
  int builtin;          /* 1 if builtin module (Out/In) */
  int builtinBase;      /* first builtin proc id for this module */
  /* CL_TYPE: where the type is defined (for NEW/IS/ALLOC operands) */
  int defMod;           /* module local id, 0 = current */
  int defTypeIdx;       /* index in that module's type table */
  int builtinId;        /* predefined proc id when modId == -1 */
  struct Obj *next;
  struct Obj *nextGlobal; /* chain for Module.globals (insertObj reuses ->next) */
  struct Obj *nextParam;  /* chain for Proc/Obj params list */
} Obj;

/* Procedure in a module */
typedef struct {
  char name[64];
  int exported, isBody;
  int nparams, capparams;
  Obj **params;         /* array of param Objs */
  int nlocals;          /* total slots incl. params */
  int hasResult;        /* function procedure (extension) */
  Type *result;         /* result type */
  Buf code;
} Proc;

typedef struct {
  Type *t;
  char name[64];
  int exported;
  int idx; /* index in module type table */
} TypeDef;

typedef struct Module {
  char name[64];
  char **imports;       /* imported module names */
  int nimports, capimports;
  Proc *procs;
  int nprocs, capprocs;
  TypeDef *types;
  int ntypes, captypes;
  Obj *globals;         /* global var Objs (linked) */
  int globalSize;       /* cells */
  char **strings;       /* string literal pool */
  int nstrings, capstrings;
  int tagCounter;
  int procLevel;        /* current proc nesting level while parsing */
} Module;

/* ---- model.c ---- */
Type *newType(int kind);
extern Type *typeInt, *typeReal, *typeBool, *typeChar, *typeSet, *typeNil, *typeLongint;
extern Type *typeCharArrayAny; /* marker: any ARRAY OF CHAR (Out.String, In.Line, COPY) */
extern Type *typeAnyPointer;   /* marker: any pointer (DISPOSE param) */
void initBasicTypes(void);
extern int gTypeStamp; /* incremented by writeModule; type registration guard */
int typeSizeCells(Type *t);          /* slots occupied inline (always 1 in v1) */
int typeEquals(Type *a, Type *b);
int typeAssignable(Type *dst, Type *src); /* src value assignable to dst var */
Field *findField(Type *rec, const char *name);
int recordPayload(Type *rec);

Obj *newObj(const char *name, int cls);
void scopePush(void);
void scopePop(void);
void insertObj(Obj *o);             /* into current scope, error on duplicate */
Obj *lookup(const char *name);      /* walk scopes */
Obj *lookupIn(Obj *list, const char *name);

extern Obj *scopeStack[64];
extern int scopeTop;
extern Module *curMod;
extern Proc *curProc;

/* type table helpers */
int typeIndex(Module *m, Type *t);  /* register if needed, return index */
Type *mkArrayType(Type *elem, int ndim, int *dims);
Type *mkOpenArrayType(Type *elem); /* formal param "ARRAY OF T" */
Type *mkPointerType(Type *to);
Type *mkRecordType(void);
void completeRecord(Type *rec, Type *base, Field *fields, int nfields);

#endif
