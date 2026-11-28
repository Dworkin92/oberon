/* ob2c.c - transpiler .obc -> C.
   Reads a compiled module (plus its imports) and emits a standalone C file:
   one C function per procedure with the bytecode UNROLLED to straight-line C
   (explicit value stack, goto for jumps), a procTab[] of function pointers for
   CALL, and a main() that loads the .obc via the shared runtime (rt.c) and
   calls the module body directly instead of running the interpreter loop.
   Build the result with:  gcc -O2 -Isrc gen.c src/rt.c src/ob.c src/model.c src/module.c -lm
   usage: ob2c <file.obc> [-o out.c] */
#include "rt.h"

static FILE *out;
static void E(const char *fmt, ...) {
  va_list ap; va_start(ap, fmt);
  vfprintf(out, fmt, ap);
  va_end(ap);
}

static uint32_t rd32(const unsigned char *c, int *pc) {
  uint32_t v = (uint32_t)c[*pc] | ((uint32_t)c[*pc+1] << 8) |
               ((uint32_t)c[*pc+2] << 16) | ((uint32_t)c[*pc+3] << 24);
  *pc += 4;
  return v;
}
static uint64_t rd64(const unsigned char *c, int *pc) {
  uint64_t v = 0;
  for (int i = 0; i < 8; i++) v |= (uint64_t)c[*pc + i] << (8 * i);
  *pc += 8;
  return v;
}

/* operand byte length per opcode (for the jump-target pre-pass) */
static int operandLen(int op) {
  switch (op) {
    case OP_CONST_I: case OP_CONST_S:
    case OP_LOAD_LOCAL: case OP_STORE_LOCAL: case OP_ADDR_LOCAL:
    case OP_LEN: case OP_COPY:
    case OP_JMP: case OP_JZ: case OP_JNZ:
      return 4;
    case OP_CONST_R: case OP_CONST_L:
      return 8;
    case OP_LOAD_GLOBAL: case OP_STORE_GLOBAL: case OP_ADDR_GLOBAL:
    case OP_NEW: case OP_ALLOC_ARRAY: case OP_ISTYPE: case OP_CHECKTYPE: case OP_DISPOSE:
      return 5; /* u8 mod + u32 */
    case OP_CALL:
      return 12;
    case OP_PROCVAL:
      return 12;
    default:
      return 0;
  }
}


/* ---------- module walk (same DFS pre-order as vm.c loadMod, so gid match) ---------- */
typedef struct { LoadedModule *lm; int gid; } MEnt;
static MEnt gMods[128];
static int gNMods;

static void walk(const char *name, const char *dir) {
  for (int i = 0; i < gNMods; i++)
    if (!strcmp(gMods[i].lm->name, name)) return;
  char path[600];
  if (!findModuleFile(name, dir, 0, path, sizeof path)) { fprintf(stderr, "ob2c: cannot find %s.obc from %s\n", name, dir); exit(1); }
  LoadedModule *lm = loadModuleFile(path);
  if (!lm) { fprintf(stderr, "ob2c: cannot load %s\n", path); exit(1); }
  gMods[gNMods].lm = lm;
  gMods[gNMods].gid = gNMods;
  gNMods++;
  for (int i = 0; i < lm->nimports; i++) walk(lm->imports[i], dir);
}

/* ---------- per-procedure code emission ---------- */
static void emitProc(int gid, int pidx, LProc *lp) {
  unsigned char *c = lp->code;
  int n = lp->codelen;
  char *isT = calloc(n ? (size_t)n : 1, 1);
  int pc = 0;
  while (pc < n) { /* pre-pass: collect jump targets */
    int op = c[pc++];
    if (op == OP_JMP || op == OP_JZ || op == OP_JNZ) {
      uint32_t t = rd32(c, &pc);
      if (t < (uint32_t)n) isT[t] = 1;
    } else if (op == OP_JUMPTABLE) {
      uint32_t cnt = rd32(c, &pc);
      rd32(c, &pc); /* base */
      uint32_t def = rd32(c, &pc);
      if (def < (uint32_t)n) isT[def] = 1;
      for (uint32_t i = 0; i < cnt; i++) {
        uint32_t t = rd32(c, &pc);
        if (t < (uint32_t)n) isT[t] = 1;
      }
    } else pc += operandLen(op);
  }
  E("static void f%d_%d(VM *vm) {\n", gid, pidx);
  E("  Frame *fr = &vm->frames[vm->fp - 1];\n");
  E("  VMMod *cur = vm->mods[fr->mod];\n");
  E("  (void)fr; (void)cur;\n");
  pc = 0;
  while (pc < n) {
    int here = pc;
    if (isT[here]) E("L%d: ;\n", here);
    int op = c[pc++];
    uint32_t a, b, cc;
    switch (op) {
      case OP_NOP: E("  ;\n"); break;
      case OP_CONST_I:
        a = rd32(c, &pc);
        E("  push(vm, (Cell)(int32_t)%d);\n", (int32_t)a);
        break;
      case OP_CONST_R: {
        uint64_t u = rd64(c, &pc);
        E("  push(vm, (Cell)(int64_t)UINT64_C(0x%llX));\n", (unsigned long long)u);
        break;
      }
      case OP_CONST_L: {
        uint64_t u = rd64(c, &pc);
        E("  push(vm, (Cell)(int64_t)UINT64_C(0x%llX));\n", (unsigned long long)u);
        break;
      }
      case OP_CONST_S:
        a = rd32(c, &pc);
        E("  push(vm, cur->strRefs[%uu]);\n", a);
        break;
      case OP_LOAD_LOCAL: case OP_STORE_LOCAL: case OP_ADDR_LOCAL: {
        a = rd32(c, &pc);
        int ld = (int)(a >> 16), off = (int)(a & 0xFFFF);
        E("  { int ld = %d, off = %d; int fi = vm->fp - 1;\n"
          "    while (ld-- > 0) { fi = vm->frames[fi].slink; if (fi < 0) vmRuntimeError(vm, \"bad static link\"); }\n"
          "    int slot = vm->frames[fi].base + off;\n", ld, off);
        if (op == OP_LOAD_LOCAL)      E("    push(vm, vm->stack[slot]); }\n");
        else if (op == OP_STORE_LOCAL) E("    vm->stack[slot] = pop(vm); }\n");
        else                           E("    push(vm, MK_STACK_ADDR(slot)); }\n");
        break;
      }
      case OP_LOAD_GLOBAL: case OP_STORE_GLOBAL: case OP_ADDR_GLOBAL: {
        int lmod = c[pc++];
        a = rd32(c, &pc);
        E("  { int g = cur->map[%d];\n", lmod);
        if (op == OP_LOAD_GLOBAL)       E("    push(vm, vm->mods[g]->globals[%uu]); }\n", a);
        else if (op == OP_STORE_GLOBAL) E("    vm->mods[g]->globals[%uu] = pop(vm); }\n", a);
        else                            E("    push(vm, MK_GLOBAL_ADDR(g, %uu)); } /* absolute gid */\n", a);
        break;
      }
      case OP_LOAD_AT:   E("  { Cell a = pop(vm); push(vm, memRead(vm, a)); }\n"); break;
      case OP_STORE_AT:  E("  { Cell v = pop(vm); Cell a = pop(vm); memWrite(vm, a, v); }\n"); break;
      case OP_TO_ADDR:   E("  { Cell r = pop(vm); push(vm, MK_HEAP_ADDR(r)); }\n"); break;
      case OP_IADD: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a + (int32_t)b)); }\n"); break;
      case OP_ISUB: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a - (int32_t)b)); }\n"); break;
      case OP_IMUL: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a * (int32_t)b)); }\n"); break;
      case OP_IDIV:
        E("  { Cell b = pop(vm), a = pop(vm); if (b == 0) vmRuntimeError(vm, \"division by zero\"); Cell q, r; idivmod(a, b, &q, &r); push(vm, q); }\n");
        break;
      case OP_IMOD:
        E("  { Cell b = pop(vm), a = pop(vm); if (b == 0) vmRuntimeError(vm, \"division by zero\"); Cell q, r; idivmod(a, b, &q, &r); push(vm, r); }\n");
        break;
      case OP_INEG: E("  { Cell a = pop(vm); push(vm, (Cell)(int32_t)(-(int32_t)a)); }\n"); break;
      case OP_IABS: E("  { Cell a = pop(vm); int32_t v = (int32_t)a; push(vm, v < 0 ? (Cell)(-v) : a); }\n"); break;
      case OP_IODD: E("  { Cell a = pop(vm); push(vm, ((int32_t)a) & 1); }\n"); break;
      case OP_FADD: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) + cellToDouble(b))); }\n"); break;
      case OP_FSUB: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) - cellToDouble(b))); }\n"); break;
      case OP_FMUL: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) * cellToDouble(b))); }\n"); break;
      case OP_FDIV: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) / cellToDouble(b))); }\n"); break;
      case OP_FNEG: E("  { Cell a = pop(vm); push(vm, cellFromDouble(-cellToDouble(a))); }\n"); break;
      case OP_FABS: E("  { Cell a = pop(vm); double d = cellToDouble(a); push(vm, cellFromDouble(d < 0 ? -d : d)); }\n"); break;
      case OP_FFLOOR: E("  { Cell a = pop(vm); double d = cellToDouble(a); push(vm, (Cell)(int32_t)(int64_t)floor(d)); }\n"); break;
      case OP_I2F:  E("  { Cell a = pop(vm); push(vm, cellFromDouble((double)(int32_t)a)); }\n"); break;
      case OP_F2I:  E("  { Cell a = pop(vm); double d = cellToDouble(a); push(vm, (Cell)(int32_t)(int64_t)d); }\n"); break;
      case OP_ILT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a < (int32_t)b); }\n"); break;
      case OP_ILE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a <= (int32_t)b); }\n"); break;
      case OP_IGT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a > (int32_t)b); }\n"); break;
      case OP_IGE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a >= (int32_t)b); }\n"); break;
      case OP_IEQ: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a == b); }\n"); break;
      case OP_INE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a != b); }\n"); break;
      case OP_FLT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) < cellToDouble(b)); }\n"); break;
      case OP_FLE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) <= cellToDouble(b)); }\n"); break;
      case OP_FGT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) > cellToDouble(b)); }\n"); break;
      case OP_FGE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) >= cellToDouble(b)); }\n"); break;
      case OP_FEQ: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) == cellToDouble(b)); }\n"); break;
      case OP_FNE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) != cellToDouble(b)); }\n"); break;
      case OP_EQ:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, a == b); }\n"); break;
      case OP_NE:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, a != b); }\n"); break;
      case OP_AND: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a && b); }\n"); break;
      case OP_OR:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, a || b); }\n"); break;
      case OP_NOT: E("  { Cell a = pop(vm); push(vm, !a); }\n"); break;
      case OP_SET_UNION:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, (a | b) & 0xFFFFFFFFLL); }\n"); break;
      case OP_SET_DIFF:   E("  { Cell b = pop(vm), a = pop(vm); push(vm, (a & ~b) & 0xFFFFFFFFLL); }\n"); break;
      case OP_SET_INTER:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, (a & b) & 0xFFFFFFFFLL); }\n"); break;
      case OP_SET_MEMBER:
        E("  { Cell s = pop(vm), x = pop(vm); if (x < 0 || x > 31) vmRuntimeError(vm, \"set element out of range\"); push(vm, (s >> x) & 1); }\n");
        break;
      case OP_SHL: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((uint32_t)(int32_t)a << (b & 31))); }\n"); break;
      case OP_SHR: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((uint32_t)(int32_t)a >> (b & 31))); }\n"); break;
      case OP_JMP:
        a = rd32(c, &pc);
        E("  goto L%u;\n", a);
        break;
      case OP_JZ:
        a = rd32(c, &pc);
        E("  if (pop(vm) == 0) goto L%u;\n", a);
        break;
      case OP_JNZ:
        a = rd32(c, &pc);
        E("  if (pop(vm) != 0) goto L%u;\n", a);
        break;
      case OP_CALL: {
        a = rd32(c, &pc); b = rd32(c, &pc); cc = rd32(c, &pc);
        E("  { int lmod = %u, procIdx = %u, steps = %u;\n", a, b, cc);
        E("    if (lmod == 255) {\n"
          "      int nparams = builtinNparams(procIdx);\n"
          "      int base = vm->sp - nparams;\n"
          "      callBuiltin(vm, procIdx, base, nparams);\n"
          "      vm->sp = base + (builtinHasResult(procIdx) ? 1 : 0);\n"
          "    } else {\n"
          "      int g = cur->map[lmod];\n"
          "      VMMod *callee = vm->mods[g];\n"
          "      LProc *cp = &callee->lm->procs[procIdx];\n"
          "      int base = vm->sp - cp->nparams;\n"
          "      int fi = vm->fp - 1;\n"
          "      int st = steps;\n"
          "      while (st-- > 0) { fi = vm->frames[fi].slink; if (fi < 0) break; }\n"
          "      if (vm->fp >= vm->frameCap) {\n"
          "        vm->frameCap *= 2;\n"
          "        vm->frames = realloc(vm->frames, vm->frameCap * sizeof(Frame));\n"
          "        fr = &vm->frames[vm->fp - 1];\n"
          "      }\n"
          "      Frame *nf = &vm->frames[vm->fp++];\n"
          "      nf->mod = g; nf->proc = procIdx; nf->pc = 0; nf->base = base; nf->slink = fi;\n"
          "      nf->extra = 0; nf->cref = 0;\n"
          "      vm->sp = base + cp->nlocals;\n"
          "      procTab[g][procIdx](vm);\n"
          "      fr = &vm->frames[vm->fp - 1];\n"
          "      cur = vm->mods[fr->mod];\n"
          "      if (!vm->running) return;\n"
          "    }\n"
          "  }\n");
        break;
      }
      case OP_RET:
        E("  rtLeaveFrame(vm);\n  return;\n");
        break;
      case OP_NEW: {
        int lmod = c[pc++];
        a = rd32(c, &pc);
        E("  push(vm, rtNew(vm, %d, %uu));\n", lmod, a);
        break;
      }
      case OP_DISPOSE: {
        int lmod = c[pc++];
        a = rd32(c, &pc);
        E("  rtDispose(vm, pop(vm), %d, %uu);\n", lmod, a);
        break;
      }
      case OP_PROCVAL: {
        a = rd32(c, &pc); b = rd32(c, &pc); cc = rd32(c, &pc);
        E("  push(vm, rtProcVal(vm, %u, %u, %u));\n", a, b, cc);
        break;
      }
      case OP_CALLP:
        E("  { rtCallP(vm, pop(vm));\n"
          "    Frame *tf = &vm->frames[vm->fp - 1];\n"
          "    procTab[tf->mod][tf->proc](vm);\n"
          "    fr = &vm->frames[vm->fp - 1];\n"
          "    cur = vm->mods[fr->mod];\n"
          "    if (!vm->running) return;\n"
          "  }\n");
        break;
      case OP_ALLOC_ARRAY: {
        int lmod = c[pc++];
        a = rd32(c, &pc);
        E("  { VMMod *tm = vm->mods[cur->map[%d]]; Type *t = tm->lm->types[%uu];\n"
          "    if (t->kind != TK_ARRAY) vmRuntimeError(vm, \"ALLOC_ARRAY on non-array\");\n"
          "    push(vm, allocArrayObj(vm, t)); }\n", lmod, a);
        break;
      }
      case OP_ELEM_ADDR:
        E("  { Cell acc = pop(vm); Cell ref = pop(vm);\n"
          "    if (ref == 0) vmRuntimeError(vm, \"nil pointer dereference\");\n"
          "    Cell tag = vm->heap[ref];\n"
          "    if (tag >= 0) vmRuntimeError(vm, \"indexing non-array\");\n"
          "    int ndim = (int)-tag; Cell total = vm->heap[ref + ndim + 1];\n"
          "    if (acc < 0 || acc >= total) vmRuntimeError(vm, \"index out of range\");\n"
          "    push(vm, MK_HEAP_ADDR(ref + ndim + 2 + acc)); }\n");
        break;
      case OP_LEN: {
        a = rd32(c, &pc);
        E("  { uint32_t d = %uu; Cell ref = pop(vm);\n"
          "    if (ref == 0) vmRuntimeError(vm, \"LEN of nil\");\n"
          "    Cell tag = vm->heap[ref];\n"
          "    if (tag >= 0) vmRuntimeError(vm, \"LEN of non-array\");\n"
          "    int ndim = (int)-tag;\n"
          "    if ((int)d < 0 || (int)d >= ndim) vmRuntimeError(vm, \"bad LEN dimension\");\n"
          "    push(vm, vm->heap[ref + 1 + d]); }\n", a);
        break;
      }
      case OP_ISTYPE: case OP_CHECKTYPE: {
        int lmod = c[pc++];
        a = rd32(c, &pc);
        E("  { VMMod *tm = vm->mods[cur->map[%d]]; int tag = tm->rtTag[%uu];\n"
          "    Cell ref = pop(vm); int ok = 0;\n"
          "    if (ref != 0) { int t = (int)vm->heap[ref];\n"
          "      while (t > 0) { if (t == tag) { ok = 1; break; } t = vmTagBase[t]; } }\n", lmod, a);
        if (op == OP_CHECKTYPE)
          E("    if (!ok) vmRuntimeError(vm, \"type guard failed\"); push(vm, ref); }\n");
        else
          E("    push(vm, ok); }\n");
        break;
      }
      case OP_COPY: {
        a = rd32(c, &pc);
        E("  { Cell src = pop(vm); Cell dst = pop(vm);\n"
          "    for (uint32_t i = 0; i < %uu; i++) memWrite(vm, dst + (Cell)i, memRead(vm, src + (Cell)i)); }\n", a);
        break;
      }
      case OP_COPY_STR:
        E("  { Cell dstRef = pop(vm); Cell srcRef = pop(vm);\n"
          "    if (srcRef == 0 || dstRef == 0) vmRuntimeError(vm, \"COPY with nil array\");\n"
          "    int snd = (int)-vm->heap[srcRef]; int dnd = (int)-vm->heap[dstRef];\n"
          "    int stot = (int)vm->heap[srcRef + snd + 1]; int dtot = (int)vm->heap[dstRef + dnd + 1];\n"
          "    int nn = stot < dtot ? stot : dtot;\n"
          "    int shdr = snd + 2, dhdr = dnd + 2;\n"
          "    for (int i = 0; i < nn; i++) vm->heap[dstRef + dhdr + i] = vm->heap[srcRef + shdr + i]; }\n");
        break;
      case OP_AADD: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a + b); }\n"); break;
      case OP_LADD: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a + b); }\n"); break;
      case OP_LSUB: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a - b); }\n"); break;
      case OP_LMUL: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a * b); }\n"); break;
      case OP_LDIV:
        E("  { Cell b = pop(vm), a = pop(vm); if (b == 0) vmRuntimeError(vm, \"division by zero\"); Cell q, r; idivmod(a, b, &q, &r); push(vm, q); }\n");
        break;
      case OP_LMOD:
        E("  { Cell b = pop(vm), a = pop(vm); if (b == 0) vmRuntimeError(vm, \"division by zero\"); Cell q, r; idivmod(a, b, &q, &r); push(vm, r); }\n");
        break;
      case OP_LNEG: E("  { Cell a = pop(vm); push(vm, -a); }\n"); break;
      case OP_LABS: E("  { Cell a = pop(vm); push(vm, a < 0 ? -a : a); }\n"); break;
      case OP_LODD: E("  { Cell a = pop(vm); push(vm, (int64_t)a & 1); }\n"); break;
      case OP_LLT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a < (int64_t)b); }\n"); break;
      case OP_LLE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a <= (int64_t)b); }\n"); break;
      case OP_LGT: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a > (int64_t)b); }\n"); break;
      case OP_LGE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a >= (int64_t)b); }\n"); break;
      case OP_LEQ: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a == b); }\n"); break;
      case OP_LNE: E("  { Cell b = pop(vm), a = pop(vm); push(vm, a != b); }\n"); break;
      case OP_L2I: E("  { Cell a = pop(vm); push(vm, (Cell)(int32_t)(int64_t)a); }\n"); break;
      case OP_JUMPTABLE: {
        a = rd32(c, &pc); /* n */
        uint32_t base = rd32(c, &pc), def = rd32(c, &pc);
        E("  { Cell sv = pop(vm); int32_t idx = (int32_t)sv - %d;\n", (int32_t)base);
        E("    switch (idx) {\n");
        for (uint32_t i = 0; i < a; i++) {
          uint32_t t = rd32(c, &pc);
          E("      case %u: goto L%u;\n", i, t);
        }
        E("      default: goto L%u; } }\n", def);
        break;
      }
      case OP_DUP:   E("  push(vm, peek(vm));\n"); break;
      case OP_DROP:  E("  pop(vm);\n"); break;
      case OP_SWAP:  E("  { Cell b = pop(vm), a = pop(vm); push(vm, b); push(vm, a); }\n"); break;
      default:
        fprintf(stderr, "ob2c: unsupported opcode %d in f%d_%d\n", op, gid, pidx);
        exit(1);
    }
  }
  E("  return;\n}\n\n");
  free(isT);
}

int main(int argc, char **argv) {
  const char *inPath = NULL, *outPath = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-o")) { outPath = argv[++i]; }
    else inPath = argv[i];
  }
  if (!inPath) { fprintf(stderr, "usage: ob2c <file.obc> [-o out.c]\n"); return 2; }

  initBasicTypes();

  /* dir + module name from input path (same convention as vmLoad) */
  char dir[600];
  strcpy(dir, ".");
  const char *slash = strrchr(inPath, '/');
  const char *bslash = strrchr(inPath, '\\');
  const char *sep = slash > bslash ? slash : bslash;
  if (sep) {
    size_t nn = (size_t)(sep - inPath);
    if (nn >= sizeof dir) nn = sizeof dir - 1;
    memcpy(dir, inPath, nn);
    dir[nn] = 0;
  }
  const char *base = sep ? sep + 1 : inPath;
  char name[64];
  snprintf(name, sizeof name, "%s", base);
  char *dot = strrchr(name, '.');
  if (dot) *dot = 0;

  walk(name, dir);

  if (!outPath) {
    static char def[600];
    snprintf(def, sizeof def, "%s.c", base);
    char *d2 = strrchr(def, '.');
    if (d2) strcpy(d2, ".c");
    outPath = def;
  }
  out = fopen(outPath, "w");
  if (!out) { fprintf(stderr, "ob2c: cannot write %s\n", outPath); return 1; }

  E("/* generated by ob2c from %s — do not edit.\n", inPath);
  E("   bytecode unrolled to straight-line C; runtime in rt.c.\n");
  E("   build (depuis bootstrap/): gcc -O2 -Isrc %s src/rt.c src/ob.c src/model.c src/module.c -lm\n", outPath);
  E("   run:   ./a.out <file.obc> [args...]  (the .obc is loaded for module metadata;\n");
  E("          imports resolve from the .obc's directory, as with obvm)\n */\n");
  E("#include \"rt.h\"\n");
  E("#ifdef _WIN32\n#include <fcntl.h>\n#include <io.h>\n#endif\n\n");
  E("typedef void (*ProcFn)(VM *);\n\n");

  /* forward declarations */
  for (int g = 0; g < gNMods; g++)
    for (int p = 0; p < gMods[g].lm->nprocs; p++)
      E("static void f%d_%d(VM *vm);\n", g, p);
  E("\n");

  /* per-module proc tables */
  for (int g = 0; g < gNMods; g++) {
    LoadedModule *lm = gMods[g].lm;
    E("static ProcFn tab%d[] = { ", g);
    for (int p = 0; p < lm->nprocs; p++) E("%sf%d_%d", p ? ", " : "", g, p);
    E(" };\n");
  }
  E("static ProcFn *procTab[] = { ");
  for (int g = 0; g < gNMods; g++) E("%stab%d", g ? ", " : "", g);
  E(" };\n\n");

  /* function bodies */
  for (int g = 0; g < gNMods; g++)
    for (int p = 0; p < gMods[g].lm->nprocs; p++)
      emitProc(g, p, &gMods[g].lm->procs[p]);

  /* main: like obvm, but calls the generated body proc instead of vmRun */
  E("int main(int argc, char **argv) {\n");
  E("  if (argc < 2) { fprintf(stderr, \"usage: %%s <file.obc> [args...]\\n\", argv[0]); return 2; }\n");
  E("#ifdef _WIN32\n");
  E("  _setmode(_fileno(stdout), _O_BINARY);\n");
  E("  _setmode(_fileno(stdin), _O_BINARY);\n");
  E("#endif\n");
  E("  initBasicTypes();\n");
  E("  if (setjmp(obJmp)) return 1;\n");
  E("  VM *vm = vmLoad(argv[1]);\n");
  E("  vmSetArgs(argc - 2, argv + 2);\n");
  E("  rtEnterBody(vm);\n");
  E("  while (vm->running && vm->fp > 0) {\n");
  E("    Frame *fr = &vm->frames[vm->fp - 1];\n");
  E("    procTab[fr->mod][fr->proc](vm);\n");
  E("  }\n");
  E("  fflush(stdout);\n");
  E("  return vm->haltCode;\n");
  E("}\n");

  fclose(out);
  fprintf(stderr, "ob2c: %s -> %s (%d modules)\n", inPath, outPath, gNMods);
  return 0;
}
