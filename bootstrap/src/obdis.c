/* obdis.c - disassembler for .obc bytecode files
   usage: obdis <file.obc> */
#include "ob.h"
#include "model.h"
#include "module.h"

static const char *opName(int op) {
  static const char *names[OP_COUNT] = {
    "NOP",
    "CONST_I", "CONST_R", "CONST_S",
    "LOAD_LOCAL", "STORE_LOCAL", "ADDR_LOCAL",
    "LOAD_GLOBAL", "STORE_GLOBAL", "ADDR_GLOBAL",
    "LOAD_AT", "STORE_AT", "TO_ADDR",
    "IADD", "ISUB", "IMUL", "IDIV", "IMOD", "INEG", "IABS", "IODD",
    "FADD", "FSUB", "FMUL", "FDIV", "FNEG", "FABS", "FFLOOR",
    "I2F", "F2I",
    "ILT", "ILE", "IGT", "IGE", "IEQ", "INE",
    "FLT", "FLE", "FGT", "FGE", "FEQ", "FNE",
    "EQ", "NE", "AND", "OR", "NOT",
    "SET_UNION", "SET_DIFF", "SET_INTER", "SET_MEMBER",
    "JMP", "JZ", "JNZ",
    "CALL", "RET",
    "NEW", "ALLOC_ARRAY",
    "LEN", "ISTYPE", "CHECKTYPE",
    "ELEM_ADDR", "COPY", "COPY_STR",
    "DUP", "DROP", "SWAP", "SHL", "SHR", "AADD",
    "CONST_L",
    "LADD", "LSUB", "LMUL", "LDIV", "LMOD", "LNEG", "LABS", "LODD",
    "LLT", "LLE", "LGT", "LGE", "LEQ", "LNE", "L2I",
    "JUMPTABLE"
  };
  if (op >= 0 && op < OP_COUNT) return names[op];
  return "?";
}

/* operand signature per opcode */
enum { A_NONE, A_U32, A_F64, A_I64, A_LOCAL, A_GLOBAL, A_JMP, A_CALL, A_TYPEOP, A_TABLE };
static int argKind(int op) {
  switch (op) {
    case OP_CONST_I: case OP_CONST_S: case OP_LEN: case OP_COPY: return A_U32;
    case OP_CONST_R: return A_F64;
    case OP_CONST_L: return A_I64;
    case OP_LOAD_LOCAL: case OP_STORE_LOCAL: case OP_ADDR_LOCAL: return A_LOCAL;
    case OP_LOAD_GLOBAL: case OP_STORE_GLOBAL: case OP_ADDR_GLOBAL: return A_GLOBAL;
    case OP_JMP: case OP_JZ: case OP_JNZ: return A_JMP;
    case OP_CALL: return A_CALL;
    case OP_NEW: case OP_ALLOC_ARRAY: case OP_ISTYPE: case OP_CHECKTYPE: return A_TYPEOP;
    case OP_JUMPTABLE: return A_TABLE;
    default: return A_NONE;
  }
}

static uint32_t ru32(const unsigned char *c, int *pc) {
  uint32_t v = (uint32_t)c[*pc] | ((uint32_t)c[*pc+1] << 8) |
               ((uint32_t)c[*pc+2] << 16) | ((uint32_t)c[*pc+3] << 24);
  *pc += 4;
  return v;
}

static void disasmProc(LoadedModule *lm, LProc *p, FILE *out) {
  fprintf(out, "PROC %s%s%s nparams=%d nlocals=%d\n",
          p->name, p->isBody ? " (body)" : "", p->exported ? " *" : "",
          p->nparams, p->nlocals);
  for (int j = 0; j < p->nparams; j++)
    fprintf(out, "  param %s%s : type#%d\n", p->params[j]->name,
            p->params[j]->isVarParam ? " VAR" : "", (int)(uintptr_t)p->params[j]->type);
  int pc = 0;
  while (pc < p->codelen) {
    int start = pc;
    int op = p->code[pc++];
    fprintf(out, "%5d: %-12s", start, opName(op));
    switch (argKind(op)) {
      case A_U32: fprintf(out, "%u", ru32(p->code, &pc)); break;
      case A_F64: {
        uint64_t u = 0;
        for (int i = 0; i < 8; i++) u |= (uint64_t)p->code[pc + i] << (8 * i);
        pc += 8;
        fprintf(out, "%g", cellToDouble((Cell)u));
        break;
      }
      case A_I64: {
        uint64_t u = 0;
        for (int i = 0; i < 8; i++) u |= (uint64_t)p->code[pc + i] << (8 * i);
        pc += 8;
        fprintf(out, "%lld", (long long)(int64_t)u);
        break;
      }
      case A_LOCAL: {
        uint32_t v = ru32(p->code, &pc);
        fprintf(out, "ld=%d off=%d", v >> 16, v & 0xFFFF);
        break;
      }
      case A_GLOBAL: {
        int m = p->code[pc++];
        uint32_t v = ru32(p->code, &pc);
        fprintf(out, "mod=%d off=%u", m, v);
        break;
      }
      case A_JMP: fprintf(out, "-> %u", ru32(p->code, &pc)); break;
      case A_CALL: {
        uint32_t m = ru32(p->code, &pc), pr = ru32(p->code, &pc), st = ru32(p->code, &pc);
        fprintf(out, "mod=%u proc=%u steps=%u", m, pr, st);
        break;
      }
      case A_TYPEOP: {
        int m = p->code[pc++];
        uint32_t v = ru32(p->code, &pc);
        fprintf(out, "mod=%d type=%u", m, v);
        break;
      }
      case A_TABLE: {
        uint32_t n = ru32(p->code, &pc), base = ru32(p->code, &pc), def = ru32(p->code, &pc);
        fprintf(out, "n=%u base=%u default->%u [", n, base, def);
        for (uint32_t i = 0; i < n && i < 16; i++) fprintf(out, "%s%u", i ? "," : "", ru32(p->code, &pc));
        if (n > 16) { for (uint32_t i = 16; i < n; i++) ru32(p->code, &pc); fprintf(out, ",..."); }
        fprintf(out, "]");
        break;
      }
      default: break;
    }
    fprintf(out, "\n");
  }
}

static const char *kindName(int k) {
  switch (k) {
    case TK_INT: return "INTEGER"; case TK_REAL: return "REAL";
    case TK_BOOL: return "BOOLEAN"; case TK_CHAR: return "CHAR";
    case TK_SET: return "SET"; case TK_ARRAY: return "ARRAY";
    case TK_RECORD: return "RECORD"; case TK_POINTER: return "POINTER";
    case TK_NIL: return "NIL"; case TK_LONGINT: return "LONGINT"; default: return "?";
  }
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: obdis <file.obc>\n"); return 2; }
  initBasicTypes();
  if (setjmp(obJmp)) return 1;
  LoadedModule *lm = loadModuleFile(argv[1]);
  if (!lm) { fprintf(stderr, "cannot load %s\n", argv[1]); return 1; }
  printf("MODULE %s  globals=%d cells, imports:", lm->name, lm->globalSize);
  for (int i = 0; i < lm->nimports; i++) printf(" %s", lm->imports[i]);
  printf("\n");
  printf("GLOBALS:\n");
  for (Obj *o = lm->exportedVars; o; o = o->next)
    printf("  %-16s off=%d type=%s%s\n", o->name, o->offset,
           o->type ? kindName(o->type->kind) : "?", o->exported ? " *" : "");
  printf("TYPES:\n");
  for (int i = 0; i < lm->ntypes; i++) {
    Type *t = lm->types[i];
    printf("  #%d %-8s %s", i, kindName(t->kind), t->name);
    if (t->kind == TK_ARRAY) {
      printf(" [");
      for (int d = 0; d < t->ndim; d++) printf("%s%d", d ? "," : "", t->dims[d]);
      printf("] OF type#%d", (int)(uintptr_t)t->elem);
    } else if (t->kind == TK_RECORD) {
      printf(" payload=%d base=%s fields:", t->payload, t->base ? t->base->name : "-");
      for (Field *f = t->fields; f; f = f->next)
        printf(" %s@%d", f->name, f->offset);
    } else if (t->kind == TK_POINTER) {
      printf(" TO %s", t->to ? t->to->name : "?");
    }
    printf("\n");
  }
  printf("STRINGS:\n");
  for (int i = 0; i < lm->nstrings; i++) printf("  #%d \"%s\"\n", i, lm->strings[i]);
  for (int i = 0; i < lm->nprocs; i++) {
    printf("\n");
    disasmProc(lm, &lm->procs[i], stdout);
  }
  return 0;
}
