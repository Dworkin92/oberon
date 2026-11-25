/* vm.c - boucle dinterprétation de la VM (dispatch par computed goto).
   Le runtime (chargement, tas, mémoire taggée, builtins) vit dans rt.c,
   partagé avec le code C généré par ob2c. */
#include "rt.h"

#if defined(__GNUC__) && !defined(OB_NO_COMPUTED_GOTO)
#define OB_COMPUTED_GOTO 1
#define OPLABEL(name) L_##name:
#else
#define OPLABEL(name)
#endif

/* ---------- main loop ---------- */
void vmRun(VM *vm) {

#ifdef OB_COMPUTED_GOTO
  /* computed-goto dispatch table (GCC &&label extension): one indirect jump per opcode
     instead of a switch — measurable on dispatch-heavy bytecode. Benchmark: -DOB_NO_COMPUTED_GOTO. */
  static void *const dispatchTab[OP_COUNT] = {
    [0 ... OP_COUNT - 1] = &&L_DEFAULT,
    [OP_CONST_I] = &&L_OP_CONST_I,
    [OP_CONST_R] = &&L_OP_CONST_R,
    [OP_CONST_S] = &&L_OP_CONST_S,
    [OP_LOAD_LOCAL] = &&L_OP_LOAD_LOCAL,
    [OP_STORE_LOCAL] = &&L_OP_STORE_LOCAL,
    [OP_ADDR_LOCAL] = &&L_OP_ADDR_LOCAL,
    [OP_LOAD_GLOBAL] = &&L_OP_LOAD_GLOBAL,
    [OP_STORE_GLOBAL] = &&L_OP_STORE_GLOBAL,
    [OP_ADDR_GLOBAL] = &&L_OP_ADDR_GLOBAL,
    [OP_LOAD_AT] = &&L_OP_LOAD_AT,
    [OP_STORE_AT] = &&L_OP_STORE_AT,
    [OP_TO_ADDR] = &&L_OP_TO_ADDR,
    [OP_IADD] = &&L_OP_IADD,
    [OP_ISUB] = &&L_OP_ISUB,
    [OP_IMUL] = &&L_OP_IMUL,
    [OP_IDIV] = &&L_OP_IDIV,
    [OP_IMOD] = &&L_OP_IMOD,
    [OP_INEG] = &&L_OP_INEG,
    [OP_IABS] = &&L_OP_IABS,
    [OP_IODD] = &&L_OP_IODD,
    [OP_FADD] = &&L_OP_FADD,
    [OP_FSUB] = &&L_OP_FSUB,
    [OP_FMUL] = &&L_OP_FMUL,
    [OP_FDIV] = &&L_OP_FDIV,
    [OP_FNEG] = &&L_OP_FNEG,
    [OP_FABS] = &&L_OP_FABS,
    [OP_FFLOOR] = &&L_OP_FFLOOR,
    [OP_I2F] = &&L_OP_I2F,
    [OP_F2I] = &&L_OP_F2I,
    [OP_ILT] = &&L_OP_ILT,
    [OP_ILE] = &&L_OP_ILE,
    [OP_IGT] = &&L_OP_IGT,
    [OP_IGE] = &&L_OP_IGE,
    [OP_IEQ] = &&L_OP_IEQ,
    [OP_INE] = &&L_OP_INE,
    [OP_FLT] = &&L_OP_FLT,
    [OP_FLE] = &&L_OP_FLE,
    [OP_FGT] = &&L_OP_FGT,
    [OP_FGE] = &&L_OP_FGE,
    [OP_FEQ] = &&L_OP_FEQ,
    [OP_FNE] = &&L_OP_FNE,
    [OP_EQ] = &&L_OP_EQ,
    [OP_NE] = &&L_OP_NE,
    [OP_AND] = &&L_OP_AND,
    [OP_OR] = &&L_OP_OR,
    [OP_NOT] = &&L_OP_NOT,
    [OP_SET_UNION] = &&L_OP_SET_UNION,
    [OP_SET_DIFF] = &&L_OP_SET_DIFF,
    [OP_SET_INTER] = &&L_OP_SET_INTER,
    [OP_SET_MEMBER] = &&L_OP_SET_MEMBER,
    [OP_SHL] = &&L_OP_SHL,
    [OP_SHR] = &&L_OP_SHR,
    [OP_JMP] = &&L_OP_JMP,
    [OP_JZ] = &&L_OP_JZ,
    [OP_JNZ] = &&L_OP_JNZ,
    [OP_CALL] = &&L_OP_CALL,
    [OP_RET] = &&L_OP_RET,
    [OP_NEW] = &&L_OP_NEW,
    [OP_ALLOC_ARRAY] = &&L_OP_ALLOC_ARRAY,
    [OP_ELEM_ADDR] = &&L_OP_ELEM_ADDR,
    [OP_LEN] = &&L_OP_LEN,
    [OP_ISTYPE] = &&L_OP_ISTYPE,
    [OP_CHECKTYPE] = &&L_OP_CHECKTYPE,
    [OP_COPY] = &&L_OP_COPY,
    [OP_COPY_STR] = &&L_OP_COPY_STR,
    [OP_AADD] = &&L_OP_AADD,
    [OP_CONST_L] = &&L_OP_CONST_L,
    [OP_LADD] = &&L_OP_LADD,
    [OP_LSUB] = &&L_OP_LSUB,
    [OP_LMUL] = &&L_OP_LMUL,
    [OP_LDIV] = &&L_OP_LDIV,
    [OP_LMOD] = &&L_OP_LMOD,
    [OP_LNEG] = &&L_OP_LNEG,
    [OP_LABS] = &&L_OP_LABS,
    [OP_LODD] = &&L_OP_LODD,
    [OP_LLT] = &&L_OP_LLT,
    [OP_LLE] = &&L_OP_LLE,
    [OP_LGT] = &&L_OP_LGT,
    [OP_LGE] = &&L_OP_LGE,
    [OP_LEQ] = &&L_OP_LEQ,
    [OP_LNE] = &&L_OP_LNE,
    [OP_L2I] = &&L_OP_L2I,
    [OP_DUP] = &&L_OP_DUP,
    [OP_DROP] = &&L_OP_DROP,
    [OP_SWAP] = &&L_OP_SWAP,
    [OP_NOP] = &&L_OP_NOP,
    [OP_JUMPTABLE] = &&L_OP_JUMPTABLE,
    [OP_DISPOSE] = &&L_OP_DISPOSE,
  };
#endif
  rtEnterBody(vm);

  while (vm->running && vm->fp > 0) {
    Frame *fr = &vm->frames[vm->fp - 1];
    VMMod *cur = vm->mods[fr->mod];
    LProc *pr = &cur->lm->procs[fr->proc];
    unsigned char *code = pr->code;
    int pc = fr->pc;
    int op = code[pc++];
    uint32_t u32a = 0, u32b = 0, u32c = 0;
#ifdef OB_COMPUTED_GOTO
    goto *dispatchTab[op];
#endif
    switch (op) {
      case OP_CONST_I: OPLABEL(OP_CONST_I)
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        push(vm, (Cell)(int32_t)u32a);
        break;
      case OP_CONST_R: OPLABEL(OP_CONST_R) {
        uint64_t u = 0;
        for (int i = 0; i < 8; i++) u |= (uint64_t)code[pc + i] << (8 * i);
        pc += 8;
        push(vm, (Cell)u);
        break;
      }
      case OP_CONST_S: OPLABEL(OP_CONST_S)
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        push(vm, cur->strRefs[u32a]);
        break;
      case OP_LOAD_LOCAL: OPLABEL(OP_LOAD_LOCAL) case OP_STORE_LOCAL: OPLABEL(OP_STORE_LOCAL) case OP_ADDR_LOCAL: OPLABEL(OP_ADDR_LOCAL) {
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        int ld = (int)(u32a >> 16), off = (int)(u32a & 0xFFFF);
        int fi = vm->fp - 1;
        while (ld-- > 0) { fi = vm->frames[fi].slink; if (fi < 0) vmRuntimeError(vm, "bad static link"); }
        int slot = vm->frames[fi].base + off;
        if (op == OP_LOAD_LOCAL) push(vm, vm->stack[slot]);
        else if (op == OP_STORE_LOCAL) vm->stack[slot] = pop(vm);
        else push(vm, MK_STACK_ADDR(slot));
        break;
      }
      case OP_LOAD_GLOBAL: OPLABEL(OP_LOAD_GLOBAL) case OP_STORE_GLOBAL: OPLABEL(OP_STORE_GLOBAL) case OP_ADDR_GLOBAL: OPLABEL(OP_ADDR_GLOBAL) {
        int lmod = code[pc++];
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        int g = cur->map[lmod];
        if (op == OP_LOAD_GLOBAL) push(vm, vm->mods[g]->globals[u32a]);
        else if (op == OP_STORE_GLOBAL) vm->mods[g]->globals[u32a] = pop(vm);
        else push(vm, MK_GLOBAL_ADDR(g, u32a)); /* absolute gid: valid across modules */
        break;
      }
      case OP_LOAD_AT: OPLABEL(OP_LOAD_AT) { Cell a = pop(vm); push(vm, memRead(vm, a)); break; }
      case OP_STORE_AT: OPLABEL(OP_STORE_AT) { Cell v = pop(vm); Cell a = pop(vm); memWrite(vm, a, v); break; }
      case OP_TO_ADDR: OPLABEL(OP_TO_ADDR) { Cell r = pop(vm); push(vm, MK_HEAP_ADDR(r)); break; }
      case OP_IADD: OPLABEL(OP_IADD) { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a + (int32_t)b)); break; }
      case OP_ISUB: OPLABEL(OP_ISUB) { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a - (int32_t)b)); break; }
      case OP_IMUL: OPLABEL(OP_IMUL) { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((int32_t)a * (int32_t)b)); break; }
      case OP_IDIV: OPLABEL(OP_IDIV) {
        Cell b = pop(vm), a = pop(vm);
        if (b == 0) vmRuntimeError(vm, "division by zero");
        Cell q, r; idivmod(a, b, &q, &r);
        push(vm, q);
        break;
      }
      case OP_IMOD: OPLABEL(OP_IMOD) {
        Cell b = pop(vm), a = pop(vm);
        if (b == 0) vmRuntimeError(vm, "division by zero");
        Cell q, r; idivmod(a, b, &q, &r);
        push(vm, r);
        break;
      }
      case OP_INEG: OPLABEL(OP_INEG) { Cell a = pop(vm); push(vm, (Cell)(int32_t)(-(int32_t)a)); break; }
      case OP_IABS: OPLABEL(OP_IABS) { Cell a = pop(vm); int32_t v = (int32_t)a; push(vm, v < 0 ? (Cell)(-v) : a); break; }
      case OP_IODD: OPLABEL(OP_IODD) { Cell a = pop(vm); push(vm, ((int32_t)a) & 1); break; }
      case OP_FADD: OPLABEL(OP_FADD) { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) + cellToDouble(b))); break; }
      case OP_FSUB: OPLABEL(OP_FSUB) { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) - cellToDouble(b))); break; }
      case OP_FMUL: OPLABEL(OP_FMUL) { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) * cellToDouble(b))); break; }
      case OP_FDIV: OPLABEL(OP_FDIV) { Cell b = pop(vm), a = pop(vm); push(vm, cellFromDouble(cellToDouble(a) / cellToDouble(b))); break; }
      case OP_FNEG: OPLABEL(OP_FNEG) { Cell a = pop(vm); push(vm, cellFromDouble(-cellToDouble(a))); break; }
      case OP_FABS: OPLABEL(OP_FABS) { Cell a = pop(vm); double d = cellToDouble(a); push(vm, cellFromDouble(d < 0 ? -d : d)); break; }
      case OP_FFLOOR: OPLABEL(OP_FFLOOR) { Cell a = pop(vm); double d = cellToDouble(a); push(vm, (Cell)(int32_t)(int64_t)floor(d)); break; }
      case OP_I2F: OPLABEL(OP_I2F) { Cell a = pop(vm); push(vm, cellFromDouble((double)(int32_t)a)); break; }
      case OP_F2I: OPLABEL(OP_F2I) { Cell a = pop(vm); double d = cellToDouble(a); push(vm, (Cell)(int32_t)(int64_t)d); break; }
      case OP_ILT: OPLABEL(OP_ILT) { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a < (int32_t)b); break; }
      case OP_ILE: OPLABEL(OP_ILE) { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a <= (int32_t)b); break; }
      case OP_IGT: OPLABEL(OP_IGT) { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a > (int32_t)b); break; }
      case OP_IGE: OPLABEL(OP_IGE) { Cell b = pop(vm), a = pop(vm); push(vm, (int32_t)a >= (int32_t)b); break; }
      case OP_IEQ: OPLABEL(OP_IEQ) { Cell b = pop(vm), a = pop(vm); push(vm, a == b); break; }
      case OP_INE: OPLABEL(OP_INE) { Cell b = pop(vm), a = pop(vm); push(vm, a != b); break; }
      case OP_FLT: OPLABEL(OP_FLT) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) < cellToDouble(b)); break; }
      case OP_FLE: OPLABEL(OP_FLE) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) <= cellToDouble(b)); break; }
      case OP_FGT: OPLABEL(OP_FGT) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) > cellToDouble(b)); break; }
      case OP_FGE: OPLABEL(OP_FGE) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) >= cellToDouble(b)); break; }
      case OP_FEQ: OPLABEL(OP_FEQ) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) == cellToDouble(b)); break; }
      case OP_FNE: OPLABEL(OP_FNE) { Cell b = pop(vm), a = pop(vm); push(vm, cellToDouble(a) != cellToDouble(b)); break; }
      case OP_EQ: OPLABEL(OP_EQ) { Cell b = pop(vm), a = pop(vm); push(vm, a == b); break; }
      case OP_NE: OPLABEL(OP_NE) { Cell b = pop(vm), a = pop(vm); push(vm, a != b); break; }
      case OP_AND: OPLABEL(OP_AND) { Cell b = pop(vm), a = pop(vm); push(vm, a && b); break; }
      case OP_OR: OPLABEL(OP_OR) { Cell b = pop(vm), a = pop(vm); push(vm, a || b); break; }
      case OP_NOT: OPLABEL(OP_NOT) { Cell a = pop(vm); push(vm, !a); break; }
      case OP_SET_UNION: OPLABEL(OP_SET_UNION) { Cell b = pop(vm), a = pop(vm); push(vm, (a | b) & 0xFFFFFFFFLL); break; }
      case OP_SET_DIFF: OPLABEL(OP_SET_DIFF) { Cell b = pop(vm), a = pop(vm); push(vm, (a & ~b) & 0xFFFFFFFFLL); break; }
      case OP_SET_INTER: OPLABEL(OP_SET_INTER) { Cell b = pop(vm), a = pop(vm); push(vm, (a & b) & 0xFFFFFFFFLL); break; }
      case OP_SET_MEMBER: OPLABEL(OP_SET_MEMBER) {
        Cell s = pop(vm), x = pop(vm);
        if (x < 0 || x > 31) vmRuntimeError(vm, "set element out of range");
        push(vm, (s >> x) & 1);
        break;
      }
      case OP_SHL: OPLABEL(OP_SHL) { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((uint32_t)(int32_t)a << (b & 31))); break; }
      case OP_SHR: OPLABEL(OP_SHR) { Cell b = pop(vm), a = pop(vm); push(vm, (Cell)(int32_t)((uint32_t)(int32_t)a >> (b & 31))); break; }
      case OP_JMP: OPLABEL(OP_JMP)
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc = (int)u32a;
        break;
      case OP_JZ: OPLABEL(OP_JZ)
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        if (pop(vm) == 0) pc = (int)u32a;
        break;
      case OP_JNZ: OPLABEL(OP_JNZ)
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        if (pop(vm) != 0) pc = (int)u32a;
        break;
      case OP_CALL: OPLABEL(OP_CALL) {
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        u32b = (uint32_t)code[pc+4] | ((uint32_t)code[pc+5] << 8) |
               ((uint32_t)code[pc+6] << 16) | ((uint32_t)code[pc+7] << 24);
        u32c = (uint32_t)code[pc+8] | ((uint32_t)code[pc+9] << 8) |
               ((uint32_t)code[pc+10] << 16) | ((uint32_t)code[pc+11] << 24);
        pc += 12;
        fr->pc = pc;
        int lmod = (int)u32a, procIdx = (int)u32b, steps = (int)u32c;
        if (lmod == 255) {
          int nparams = builtinNparams(procIdx);
          int base = vm->sp - nparams;
          callBuiltin(vm, procIdx, base, nparams);
          /* function builtins wrote their result at stack[base] */
          vm->sp = base + (builtinHasResult(procIdx) ? 1 : 0);
          break;
        }
        int g = cur->map[lmod];
        VMMod *callee = vm->mods[g];
        LProc *cp = &callee->lm->procs[procIdx];
        int base = vm->sp - cp->nparams;
        int fi = vm->fp - 1;
        while (steps-- > 0) { fi = vm->frames[fi].slink; if (fi < 0) break; }
        if (vm->fp >= vm->frameCap) {
          vm->frameCap *= 2;
          vm->frames = realloc(vm->frames, vm->frameCap * sizeof(Frame));
          fr = &vm->frames[vm->fp - 1]; /* realloc may move */
        }
        Frame *nf = &vm->frames[vm->fp++];
        nf->mod = g; nf->proc = procIdx; nf->pc = 0; nf->base = base; nf->slink = fi;
        vm->sp = base + cp->nlocals;
        pc = 0;
        break;
      }
      case OP_RET: OPLABEL(OP_RET) {
        Frame *old = &vm->frames[vm->fp - 1];
        LProc *oldp = &vm->mods[old->mod]->lm->procs[old->proc];
        Cell rv = oldp->hasResult ? pop(vm) : 0;
        vm->sp = old->base;
        vm->fp--;
        if (vm->fp == 0) { vm->running = 0; break; }
        if (oldp->hasResult) push(vm, rv);
        fr = &vm->frames[vm->fp - 1];
        pc = fr->pc;
        break;
      }
      case OP_NEW: OPLABEL(OP_NEW) {
        int lmod = code[pc++];
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        push(vm, rtNew(vm, lmod, (int)u32a));
        break;
      }
      case OP_DISPOSE: OPLABEL(OP_DISPOSE) {
        int lmod = code[pc++];
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        Cell addr = pop(vm);
        rtDispose(vm, addr, lmod, (int)u32a);
        break;
      }
      case OP_ALLOC_ARRAY: OPLABEL(OP_ALLOC_ARRAY) {
        int lmod = code[pc++];
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        VMMod *tm = vm->mods[cur->map[lmod]];
        Type *t = tm->lm->types[u32a];
        if (t->kind != TK_ARRAY) vmRuntimeError(vm, "ALLOC_ARRAY on non-array");
        push(vm, allocArrayObj(vm, t));
        break;
      }
      case OP_ELEM_ADDR: OPLABEL(OP_ELEM_ADDR) {
        Cell acc = pop(vm);
        Cell ref = pop(vm);
        if (ref == 0) vmRuntimeError(vm, "nil pointer dereference");
        Cell tag = vm->heap[ref];
        if (tag >= 0) vmRuntimeError(vm, "indexing non-array");
        int ndim = (int)-tag;
        Cell total = vm->heap[ref + ndim + 1];
        if (acc < 0 || acc >= total) vmRuntimeError(vm, "index out of range");
        push(vm, MK_HEAP_ADDR(ref + ndim + 2 + acc));
        break;
      }
      case OP_LEN: OPLABEL(OP_LEN) {
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        Cell ref = pop(vm);
        if (ref == 0) vmRuntimeError(vm, "LEN of nil");
        Cell tag = vm->heap[ref];
        if (tag >= 0) vmRuntimeError(vm, "LEN of non-array");
        int ndim = (int)-tag;
        if ((int)u32a < 0 || (int)u32a >= ndim) vmRuntimeError(vm, "bad LEN dimension");
        push(vm, vm->heap[ref + 1 + u32a]);
        break;
      }
      case OP_ISTYPE: OPLABEL(OP_ISTYPE) case OP_CHECKTYPE: OPLABEL(OP_CHECKTYPE) {
        int lmod = code[pc++];
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        VMMod *tm = vm->mods[cur->map[lmod]];
        int tag = tm->rtTag[u32a];
        Cell ref = pop(vm);
        int ok = 0;
        if (ref != 0) {
          int t = (int)vm->heap[ref];
          while (t > 0) {
            if (t == tag) { ok = 1; break; }
            t = vmTagBase[t];
          }
        }
        if (op == OP_CHECKTYPE) {
          if (!ok) vmRuntimeError(vm, "type guard failed");
          push(vm, ref); /* guard keeps the reference on the stack */
        } else {
          push(vm, ok);
        }
        break;
      }
      case OP_COPY: OPLABEL(OP_COPY) {
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        pc += 4;
        Cell src = pop(vm);
        Cell dst = pop(vm);
        for (uint32_t i = 0; i < u32a; i++)
          memWrite(vm, dst + (Cell)i, memRead(vm, src + (Cell)i));
        break;
      }
      case OP_COPY_STR: OPLABEL(OP_COPY_STR) {
        Cell dstRef = pop(vm);
        Cell srcRef = pop(vm);
        if (srcRef == 0 || dstRef == 0) vmRuntimeError(vm, "COPY with nil array");
        int snd = (int)-vm->heap[srcRef];
        int dnd = (int)-vm->heap[dstRef];
        int stot = (int)vm->heap[srcRef + snd + 1];
        int dtot = (int)vm->heap[dstRef + dnd + 1];
        int n = stot < dtot ? stot : dtot;
        int shdr = snd + 2, dhdr = dnd + 2;
        for (int i = 0; i < n; i++)
          vm->heap[dstRef + dhdr + i] = vm->heap[srcRef + shdr + i];
        break;
      }
      case OP_AADD: OPLABEL(OP_AADD) { Cell b = pop(vm), a = pop(vm); push(vm, a + b); break; }
      case OP_CONST_L: OPLABEL(OP_CONST_L) {
        uint64_t u = 0;
        for (int i = 0; i < 8; i++) u |= (uint64_t)code[pc + i] << (8 * i);
        pc += 8;
        push(vm, (Cell)(int64_t)u);
        break;
      }
      case OP_LADD: OPLABEL(OP_LADD) { Cell b = pop(vm), a = pop(vm); push(vm, a + b); break; }
      case OP_LSUB: OPLABEL(OP_LSUB) { Cell b = pop(vm), a = pop(vm); push(vm, a - b); break; }
      case OP_LMUL: OPLABEL(OP_LMUL) { Cell b = pop(vm), a = pop(vm); push(vm, a * b); break; }
      case OP_LDIV: OPLABEL(OP_LDIV) {
        Cell b = pop(vm), a = pop(vm);
        if (b == 0) vmRuntimeError(vm, "division by zero");
        Cell q, r; idivmod(a, b, &q, &r);
        push(vm, q);
        break;
      }
      case OP_LMOD: OPLABEL(OP_LMOD) {
        Cell b = pop(vm), a = pop(vm);
        if (b == 0) vmRuntimeError(vm, "division by zero");
        Cell q, r; idivmod(a, b, &q, &r);
        push(vm, r);
        break;
      }
      case OP_LNEG: OPLABEL(OP_LNEG) { Cell a = pop(vm); push(vm, -a); break; }
      case OP_LABS: OPLABEL(OP_LABS) { Cell a = pop(vm); push(vm, a < 0 ? -a : a); break; }
      case OP_LODD: OPLABEL(OP_LODD) { Cell a = pop(vm); push(vm, (int64_t)a & 1); break; }
      case OP_LLT: OPLABEL(OP_LLT) { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a < (int64_t)b); break; }
      case OP_LLE: OPLABEL(OP_LLE) { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a <= (int64_t)b); break; }
      case OP_LGT: OPLABEL(OP_LGT) { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a > (int64_t)b); break; }
      case OP_LGE: OPLABEL(OP_LGE) { Cell b = pop(vm), a = pop(vm); push(vm, (int64_t)a >= (int64_t)b); break; }
      case OP_LEQ: OPLABEL(OP_LEQ) { Cell b = pop(vm), a = pop(vm); push(vm, a == b); break; }
      case OP_LNE: OPLABEL(OP_LNE) { Cell b = pop(vm), a = pop(vm); push(vm, a != b); break; }
      case OP_L2I: OPLABEL(OP_L2I) { Cell a = pop(vm); push(vm, (Cell)(int32_t)(int64_t)a); break; }
      case OP_JUMPTABLE: OPLABEL(OP_JUMPTABLE) {
        /* u32 n, u32 base, u32 default, n x u32 targets */
        u32a = (uint32_t)code[pc] | ((uint32_t)code[pc+1] << 8) |
               ((uint32_t)code[pc+2] << 16) | ((uint32_t)code[pc+3] << 24);
        u32b = (uint32_t)code[pc+4] | ((uint32_t)code[pc+5] << 8) |
               ((uint32_t)code[pc+6] << 16) | ((uint32_t)code[pc+7] << 24);
        u32c = (uint32_t)code[pc+8] | ((uint32_t)code[pc+9] << 8) |
               ((uint32_t)code[pc+10] << 16) | ((uint32_t)code[pc+11] << 24);
        pc += 12;
        Cell v = pop(vm);
        int32_t idx = (int32_t)v - (int32_t)u32b;
        if (idx >= 0 && idx < (int32_t)u32a) {
          int tp = pc + 4 * idx;
          pc = (int)((uint32_t)code[tp] | ((uint32_t)code[tp+1] << 8) |
                     ((uint32_t)code[tp+2] << 16) | ((uint32_t)code[tp+3] << 24));
        } else pc = (int)u32c;
        break;
      }
      case OP_DUP: OPLABEL(OP_DUP) push(vm, peek(vm)); break;
      case OP_DROP: OPLABEL(OP_DROP) pop(vm); break;
      case OP_SWAP: OPLABEL(OP_SWAP) {
        Cell b = pop(vm), a = pop(vm);
        push(vm, b); push(vm, a);
        break;
      }
      case OP_NOP: OPLABEL(OP_NOP) break;
      default: OPLABEL(DEFAULT)
        vmRuntimeError(vm, "bad opcode");
    }
    if (vm->fp > 0) vm->frames[vm->fp - 1].pc = pc;
  }
}

