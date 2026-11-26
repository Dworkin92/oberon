/* rt.h - runtime partagé par la VM (vm.c) et le code C généré (ob2c).
   Contient les structures de la machine (VM, Frame, VMMod), le loader,
   le tas, la mémoire taggée et les builtins (Out/In/Files/SYSTEM). */
#ifndef RT_H
#define RT_H

#include <math.h>
#include <time.h>
#include "ob.h"
#include "model.h"
#include "module.h"

typedef struct {
  LoadedModule *lm;
  int gid;
  int *map;        /* local module id (0=self,1..n=imports) -> global id */
  Cell *globals;   /* global segment */
  int *rtTag;      /* per type idx: runtime tag (records), else 0 */
  int *rtPtrTag;   /* per pointer type idx: runtime tag of pointee record */
  int *rtPtrSize;  /* per pointer type idx: payload cells of pointee record */
  int *strRefs;    /* string pool: heap refs */
} VMMod;

typedef struct {
  int mod, proc, pc, base, slink;
  int extra;  /* OP_CALLP closure: number of captured frames to pop on RET */
  int cref;   /* OP_CALLP closure: heap ref of the closure object (for write-back), else 0 */
} Frame;

typedef struct {
  VMMod **mods;
  int nmods, capmods;
  Cell *heap;
  size_t heapCap, heapUsed;
  int freeHead;    /* free-list of heap blocks: heap[h]=0 (marker), heap[h+1]=size, heap[h+2]=next; 0 = empty */
  Cell *stack;
  size_t stackCap;
  int sp;
  Frame *frames;
  int fp, frameCap;
  int running;
  int haltCode;
} VM;

/* loader / driver */
VM *vmLoad(const char *mainObcPath);
void vmSetArgs(int argc, char **argv);
void rtEnterBody(VM *vm);   /* initial frame: module 0, proc 0 (body) */
void vmRun(VM *vm);          /* interpreter loop (vm.c) */
void vmFree(VM *vm);

/* runtime primitives used by the interpreter and by generated C code.
   push/pop/peek are static inline so generated C keeps the value stack in registers. */
static inline void push(VM *vm, Cell v) {
  if ((size_t)vm->sp >= vm->stackCap) {
    vm->stackCap *= 2;
    vm->stack = realloc(vm->stack, vm->stackCap * sizeof(Cell));
  }
  vm->stack[vm->sp++] = v;
}
static inline Cell pop(VM *vm) { return vm->stack[--vm->sp]; }
static inline Cell peek(VM *vm) { return vm->stack[vm->sp - 1]; }
Cell memRead(VM *vm, Cell a);
void memWrite(VM *vm, Cell a, Cell v);
int heapAlloc(VM *vm, int n);   /* first-fit on the free list, else bump */
void heapFree(VM *vm, int ref, int size);
int heapObjSize(Type *t);        /* cells occupied by an object of type t (array or record) */
int allocArrayObj(VM *vm, Type *t);
Cell rtNew(VM *vm, int lmod, int typeidx);          /* OP_NEW: record or array pointer */
void rtDispose(VM *vm, Cell slotAddr, int lmod, int typeidx); /* OP_DISPOSE: free + NIL */
Cell rtProcVal(VM *vm, int lmod, int pidx, int steps); /* OP_PROCVAL: plain proc value or closure snapshot */
void rtCallP(VM *vm, Cell pv);                     /* OP_CALLP: indirect call through proc value */
Cell rtLeaveFrame(VM *vm);                          /* OP_RET: pop frame (+ captured frames), push result */
void idivmod(Cell a, Cell b, Cell *q, Cell *r);
void vmRuntimeError(VM *vm, const char *msg);
void callBuiltin(VM *vm, int id, int base, int nparams);
int builtinNparams(int id);
int builtinHasResult(int id);

/* tag -> base tag map for IS */
extern int *vmTagBase;
extern int vmTagBaseCap;

#endif
