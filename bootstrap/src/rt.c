/* rt.c - runtime partagé : chargement .obc, tas, mémoire taggée, pile, builtins.
   Compilé dans obvm (avec vm.c) et dans les exécutables natifs produits par ob2c. */
#include "rt.h"

int heapAlloc(VM *vm, int n);

int *vmTagBase;
int vmTagBaseCap;
static int tagCounter;

/* ---- builtin Files module ---- */
#define FILE_TAG 0x40000000 /* reserved runtime tag for Files.FileDesc (load tags start at 1) */
static FILE *fileTab[256];  /* handle = index+1, 0 = invalid */

/* ---- SYSTEM module: program arguments ---- */
static int sysArgc = 0;
static char **sysArgv = NULL;
void vmSetArgs(int argc, char **argv) { sysArgc = argc; sysArgv = argv; }

/* read a char-array ref (or string literal) into a C string */
static void refToStr(VM *vm, Cell ref, char *buf, int max) {
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

static int fileAlloc(VM *vm, FILE *fp) {
  for (int i = 0; i < 256; i++)
    if (!fileTab[i]) {
      fileTab[i] = fp;
      int handle = i + 1;
      /* allocate the FileDesc heap object: [tag, payload=2, handle, eof] */
      int h = heapAlloc(vm, 4);
      vm->heap[h] = FILE_TAG;
      vm->heap[h + 1] = 2;
      vm->heap[h + 2] = handle;
      vm->heap[h + 3] = 0;
      return h; /* the File value (ref) */
    }
  fclose(fp);
  return 0;
}

static FILE *fileOf(VM *vm, Cell ref) {
  if (!ref || vm->heap[ref] != FILE_TAG) return NULL;
  int handle = (int)vm->heap[ref + 2];
  if (handle < 1 || handle > 256) return NULL;
  return fileTab[handle - 1];
}

void vmRuntimeError(VM *vm, const char *msg) {
  Frame *f = &vm->frames[vm->fp - 1];
  VMMod *m = vm->mods[f->mod];
  fprintf(stderr, "runtime error: %s (in %s.%s, pc=%d)\n",
          msg, m->lm->name, m->lm->procs[f->proc].name, f->pc);
  vm->running = 0;
  vm->haltCode = 1;
  longjmp(obJmp, 2);
}

/* ---------- heap ---------- */
/* Free block layout: heap[h] = 0 (marker; arrays use negative, records positive),
   heap[h+1] = block size in cells, heap[h+2] = next free block (0 = end). */
int heapAlloc(VM *vm, int n) {
  int prev = 0, cur = vm->freeHead;
  while (cur) {
    int size = (int)vm->heap[cur + 1];
    if (size >= n) {
      int next = (int)vm->heap[cur + 2];
      if (size - n >= 4) { /* split: remainder stays free where the block was */
        int rem = cur + n;
        vm->heap[rem] = 0; vm->heap[rem + 1] = size - n; vm->heap[rem + 2] = next;
        if (prev) vm->heap[prev + 2] = rem; else vm->freeHead = rem;
      } else { /* take the whole block (small remainder = internal fragmentation) */
        if (prev) vm->heap[prev + 2] = next; else vm->freeHead = next;
      }
      for (int i = 0; i < n; i++) vm->heap[cur + i] = 0;
      return cur;
    }
    prev = cur;
    cur = (int)vm->heap[cur + 2];
  }
  if (vm->heapUsed + (size_t)n > vm->heapCap) {
    vm->heapCap = (vm->heapUsed + n) * 2 + 1024;
    vm->heap = realloc(vm->heap, vm->heapCap * sizeof(Cell));
  }
  int h = (int)vm->heapUsed;
  for (int i = 0; i < n; i++) vm->heap[vm->heapUsed + i] = 0;
  vm->heapUsed += n;
  return h;
}

void heapFree(VM *vm, int ref, int size) {
  if (ref <= 0 || size < 3) vmRuntimeError(vm, "bad free");
  if (vm->heap[ref] == 0) vmRuntimeError(vm, "double DISPOSE");
  vm->heap[ref] = 0;
  vm->heap[ref + 1] = size;
  vm->heap[ref + 2] = vm->freeHead;
  vm->freeHead = ref;
}

int heapObjSize(Type *t) {
  if (!t) return 0;
  if (t->kind == TK_ARRAY) return t->ndim + 2 + t->total * typeElemCells(t->elem);
  if (t->kind == TK_RECORD) return 2 + t->payload;
  return 0;
}

int allocArrayObj(VM *vm, Type *t) {
  int hdr = t->ndim + 2;
  int cells = t->total * typeElemCells(t->elem); /* header 'total' = cell count (bounds check) */
  int h = heapAlloc(vm, hdr + cells);
  vm->heap[h] = -t->ndim;
  for (int i = 0; i < t->ndim; i++) vm->heap[h + 1 + i] = t->dims[i];
  vm->heap[h + t->ndim + 1] = cells;
  return h;
}

/* OP_NEW: allocate for a pointer type (record or fixed array pointee) */
Cell rtNew(VM *vm, int lmod, int typeidx) {
  VMMod *cur = vm->mods[vm->frames[vm->fp - 1].mod];
  VMMod *tm = vm->mods[cur->map[lmod]];
  Type *pt = tm->lm->types[typeidx];
  if (pt->kind != TK_POINTER || !pt->to) vmRuntimeError(vm, "NEW on non-pointer type");
  Type *to = pt->to;
  if (to->kind == TK_RECORD) {
    int tag = tm->rtPtrTag[typeidx];
    int size = tm->rtPtrSize[typeidx];
    if (tag == 0) vmRuntimeError(vm, "NEW on non-record pointer");
    int h = heapAlloc(vm, 2 + size);
    vm->heap[h] = tag;
    vm->heap[h + 1] = size;
    return h;
  }
  if (to->kind == TK_ARRAY) {
    if (to->isOpen) vmRuntimeError(vm, "NEW on open array pointer");
    return allocArrayObj(vm, to);
  }
  vmRuntimeError(vm, "NEW on unsupported pointee");
  return 0;
}

/* OP_DISPOSE: free the object referenced by the pointer in slot `slotAddr`, set NIL */
void rtDispose(VM *vm, Cell slotAddr, int lmod, int typeidx) {
  VMMod *cur = vm->mods[vm->frames[vm->fp - 1].mod];
  VMMod *tm = vm->mods[cur->map[lmod]];
  Type *pt = tm->lm->types[typeidx];
  Cell ref = memRead(vm, slotAddr);
  if (ref != 0) {
    int size = (pt->kind == TK_POINTER && pt->to) ? heapObjSize(pt->to) : 0;
    if (size <= 0) vmRuntimeError(vm, "DISPOSE on unsupported pointee");
    heapFree(vm, (int)ref, size);
    memWrite(vm, slotAddr, 0);
  }
}

/* ---- procedural values / closures ---- */

/* OP_PROCVAL: steps == 0 -> plain tagged value MK_PROC(gid, pidx) (module-level proc).
   steps > 0 -> closure: snapshot the static-link chain from the defining frame
   (walked `steps` slinks up from the current frame) down to the root frame into
   a heap object, and push its raw ref. */
Cell rtProcVal(VM *vm, int lmod, int pidx, int steps) {
  VMMod *cur = vm->mods[vm->frames[vm->fp - 1].mod];
  int g = cur->map[lmod];
  if (steps == -1) return MK_PROC(g, pidx); /* 0xFFFFFFFF sentinel: module-level proc */
  int fi = vm->fp - 1;
  int st = steps;
  while (st-- > 0) {
    fi = vm->frames[fi].slink;
    if (fi < 0) vmRuntimeError(vm, "bad static link (closure)");
  }
  int n = 0;
  for (int j = fi; j >= 0; j = vm->frames[j].slink) n++;
  int total = 4;
  for (int j = fi; j >= 0; j = vm->frames[j].slink) {
    Frame *f = &vm->frames[j];
    total += 1 + vm->mods[f->mod]->lm->procs[f->proc].nlocals;
  }
  int ref = heapAlloc(vm, total);
  Cell *h = &vm->heap[ref];
  h[0] = CLOSURE_TAG; h[1] = g; h[2] = pidx; h[3] = n;
  int off = 4;
  for (int j = fi; j >= 0; j = vm->frames[j].slink) {
    Frame *f = &vm->frames[j];
    int nl = vm->mods[f->mod]->lm->procs[f->proc].nlocals;
    h[off++] = nl;
    for (int k = 0; k < nl; k++) h[off++] = vm->stack[f->base + k];
  }
  return (Cell)ref;
}

/* OP_CALLP: indirect call through a procedure value.
   Plain value (TAG_PROC): slink = caller frame (module-level proc).
   Closure (raw heap ref, CLOSURE_TAG): materialize the captured frames on the
   stack (root first), then push the callee frame on top with extra/cref set. */
void rtCallP(VM *vm, Cell pv) {
  if (pv == 0) vmRuntimeError(vm, "call of NIL procedure");
  int g, procIdx, slinkFi, extra = 0, cref = 0, total = 0;
  if (ADDR_TAG(pv) == TAG_PROC) {
    g = PROC_GID(pv); procIdx = PROC_IDX(pv);
  } else {
    int ref = (int)(pv & 0x00FFFFFFFFFFFFFFLL);
    if (ref <= 0 || (size_t)ref >= vm->heapUsed || vm->heap[ref] != CLOSURE_TAG)
      vmRuntimeError(vm, "call of non-procedure value");
    cref = ref;
    g = (int)vm->heap[ref + 1]; procIdx = (int)vm->heap[ref + 2];
  }
  VMMod *callee = vm->mods[g];
  LProc *cp = &callee->lm->procs[procIdx];
  int base = vm->sp - cp->nparams;
  if (cref) {
    int n = (int)vm->heap[cref + 3];
    int capBase = base + cp->nlocals;
    int *nl = malloc(sizeof(int) * (n ? n : 1));
    int *objoff = malloc(sizeof(int) * (n ? n : 1));
    int off = 4;
    for (int i = 0; i < n; i++) {
      nl[i] = (int)vm->heap[cref + off];
      objoff[i] = off;
      off += 1 + nl[i];
      total += nl[i];
    }
    if ((size_t)(capBase + total + 1) > vm->stackCap) {
      while (vm->stackCap < (size_t)(capBase + total + 1)) vm->stackCap *= 2;
      vm->stack = realloc(vm->stack, vm->stackCap * sizeof(Cell));
    }
    int bi = capBase;
    for (int i = n - 1; i >= 0; i--) {
      for (int k = 0; k < nl[i]; k++) vm->stack[bi + k] = vm->heap[cref + objoff[i] + 1 + k];
      bi += nl[i];
    }
    int prev = -1;
    for (int i = n - 1; i >= 0; i--) {
      if (vm->fp >= vm->frameCap) {
        vm->frameCap *= 2;
        vm->frames = realloc(vm->frames, vm->frameCap * sizeof(Frame));
      }
      int b = capBase;
      for (int j = i + 1; j < n; j++) b += nl[j];
      Frame *nf = &vm->frames[vm->fp++];
      nf->mod = 0; nf->proc = 0; nf->pc = 0; nf->base = b; nf->slink = prev;
      nf->extra = 0; nf->cref = 0;
      prev = vm->fp - 1;
    }
    free(nl); free(objoff);
    slinkFi = prev;
    extra = n;
  } else {
    slinkFi = vm->fp - 1;
  }
  if (vm->fp >= vm->frameCap) {
    vm->frameCap *= 2;
    vm->frames = realloc(vm->frames, vm->frameCap * sizeof(Frame));
  }
  Frame *nf = &vm->frames[vm->fp++];
  nf->mod = g; nf->proc = procIdx; nf->pc = 0; nf->base = base; nf->slink = slinkFi;
  nf->extra = extra; nf->cref = cref;
  vm->sp = base + cp->nlocals + total;
}

/* OP_RET: pop the current frame (plus captured closure frames if any), write the
   captured cells back into the closure object, restore sp and push the result. */
Cell rtLeaveFrame(VM *vm) {
  Frame *old = &vm->frames[vm->fp - 1];
  LProc *oldp = &vm->mods[old->mod]->lm->procs[old->proc];
  Cell rv = oldp->hasResult ? pop(vm) : 0;
  vm->sp = old->base;
  int ex = old->extra;
  if (old->cref) {
    Cell *h = &vm->heap[old->cref];
    int n = (int)h[3];
    int off = 4;
    int F = vm->fp - 1 - ex; /* first captured frame index */
    for (int i = 0; i < n; i++) {
      /* object frame i (youngest first) was pushed at frame index F + (n-1-i) */
      Frame *cf = &vm->frames[F + (n - 1 - i)];
      int nl = (int)h[off];
      for (int k = 0; k < nl; k++) h[off + 1 + k] = vm->stack[cf->base + k];
      off += 1 + nl;
    }
  }
  vm->fp -= 1 + ex;
  if (vm->fp <= 0) { vm->fp = 0; vm->running = 0; return rv; }
  if (oldp->hasResult) push(vm, rv);
  return rv;
}

/* ---------- memory access (tagged addresses) ---------- */
Cell memRead(VM *vm, Cell a) {
  switch (ADDR_TAG(a)) {
    case TAG_STACK:
      return vm->stack[a & 0x00FFFFFFFFFFFFFFLL];
    case TAG_HEAP:
      return vm->heap[a & 0x00FFFFFFFFFFFFFFLL];
    case TAG_GLOBAL: {
      int g = (int)((a >> 48) & 0xFF);   /* absolute module gid (resolved at ADDR_GLOBAL) */
      int off = (int)(a & 0xFFFFFFFFFFFFLL);
      return vm->mods[g]->globals[off];
    }
  }
  vmRuntimeError(vm, "bad address");
  return 0;
}

void memWrite(VM *vm, Cell a, Cell v) {
  switch (ADDR_TAG(a)) {
    case TAG_STACK:
      vm->stack[a & 0x00FFFFFFFFFFFFFFLL] = v;
      return;
    case TAG_HEAP:
      vm->heap[a & 0x00FFFFFFFFFFFFFFLL] = v;
      return;
    case TAG_GLOBAL: {
      int g = (int)((a >> 48) & 0xFF);   /* absolute module gid (resolved at ADDR_GLOBAL) */
      int off = (int)(a & 0xFFFFFFFFFFFFLL);
      vm->mods[g]->globals[off] = v;
      return;
    }
  }
  vmRuntimeError(vm, "bad address");
}

/* ---------- loading ---------- */
static VMMod *loadMod(VM *vm, const char *name, const char *dir, int *tagCounter);

static VMMod *findMod(VM *vm, const char *name) {
  for (int i = 0; i < vm->nmods; i++)
    if (!strcmp(vm->mods[i]->lm->name, name)) return vm->mods[i];
  return NULL;
}

static VMMod *loadMod(VM *vm, const char *name, const char *dir, int *tc) {
  VMMod *existing = findMod(vm, name);
  if (existing) return existing;
  char path[600];
  if (!findModuleFile(name, dir, path, sizeof path)) {
    fprintf(stderr, "cannot load module '%s' (searched from '%s')\n", name, dir);
    exit(1);
  }
  LoadedModule *lm = loadModuleFile(path);
  if (!lm) {
    fprintf(stderr, "cannot load module '%s' (%s)\n", name, path);
    exit(1);
  }
  if (vm->nmods >= 256) {
    fprintf(stderr, "too many modules (max 256: gid is stored in one address byte)\n");
    exit(1);
  }
  VMMod *m = calloc(1, sizeof(VMMod));
  m->lm = lm;
  m->gid = vm->nmods;
  if (vm->nmods >= vm->capmods) {
    vm->capmods = vm->capmods * 2 + 8;
    vm->mods = realloc(vm->mods, vm->capmods * sizeof(VMMod *));
  }
  vm->mods[vm->nmods++] = m;
  /* imports first (recursive) */
  m->map = calloc(lm->nimports + 1, sizeof(int));
  m->map[0] = m->gid;
  for (int i = 0; i < lm->nimports; i++) {
    VMMod *im = loadMod(vm, lm->imports[i], dir, tc);
    m->map[i + 1] = im->gid;
  }
  /* runtime tags for records */
  m->rtTag = calloc(lm->ntypes ? lm->ntypes : 1, sizeof(int));
  m->rtPtrTag = calloc(lm->ntypes ? lm->ntypes : 1, sizeof(int));
  m->rtPtrSize = calloc(lm->ntypes ? lm->ntypes : 1, sizeof(int));
  for (int i = 0; i < lm->ntypes; i++) {
    Type *t = lm->types[i];
    if (t->kind == TK_RECORD) {
      (*tc)++;
      m->rtTag[i] = *tc;
      if (*tc >= vmTagBaseCap) {
        vmTagBaseCap = vmTagBaseCap * 2 + 256;
        vmTagBase = realloc(vmTagBase, vmTagBaseCap * sizeof(int));
      }
      vmTagBase[*tc] = 0;
    }
  }
  /* base tags + pointer info */
  for (int i = 0; i < lm->ntypes; i++) {
    Type *t = lm->types[i];
    if (t->kind == TK_RECORD && t->base) {
      for (int j = 0; j < lm->ntypes; j++)
        if (lm->types[j] == t->base) { vmTagBase[m->rtTag[i]] = m->rtTag[j]; break; }
    }
    if (t->kind == TK_POINTER && t->to->kind == TK_RECORD) {
      for (int j = 0; j < lm->ntypes; j++)
        if (lm->types[j] == t->to) {
          m->rtPtrTag[i] = m->rtTag[j];
          m->rtPtrSize[i] = t->to->payload;
          break;
        }
    }
  }
  /* globals segment + array initialization */
  m->globals = calloc(lm->globalSize ? lm->globalSize : 1, sizeof(Cell));
  for (Obj *o = lm->exportedVars; o; o = o->next) {
    if (o->type->kind == TK_ARRAY)
      m->globals[o->offset] = allocArrayObj(vm, o->type);
  }
  /* string pool */
  m->strRefs = calloc(lm->nstrings ? lm->nstrings : 1, sizeof(int));
  for (int i = 0; i < lm->nstrings; i++) {
    int len = (int)strlen(lm->strings[i]);
    Type *st = mkArrayType(typeChar, 1, (int[]){len + 1});
    int h = allocArrayObj(vm, st);
    int hdr = 1 + 2;
    for (int j = 0; j <= len; j++) vm->heap[h + hdr + j] = (unsigned char)lm->strings[i][j];
    m->strRefs[i] = h;
  }
  return m;
}

VM *vmLoad(const char *mainObcPath) {
  initBasicTypes();
  VM *vm = calloc(1, sizeof(VM));
  vm->heapCap = 4096;
  vm->heap = calloc(vm->heapCap, sizeof(Cell));
  vm->heapUsed = 1; /* cell 0 reserved: ref 0 == NIL */
  vm->freeHead = 0;
  vm->stackCap = 65536;
  vm->stack = calloc(vm->stackCap, sizeof(Cell));
  vm->frameCap = 1024;
  vm->frames = calloc(vm->frameCap, sizeof(Frame));
  vmTagBaseCap = 256;
  vmTagBase = calloc(vmTagBaseCap, sizeof(int));
  tagCounter = 0;
  /* dir of main file */
  char dir[600];
  strcpy(dir, ".");
  const char *slash = strrchr(mainObcPath, '/');
  const char *bslash = strrchr(mainObcPath, '\\');
  const char *sep = slash > bslash ? slash : bslash;
  if (sep) {
    size_t n = sep - mainObcPath;
    if (n >= sizeof dir) n = sizeof dir - 1;
    memcpy(dir, mainObcPath, n);
    dir[n] = 0;
  }
  /* module name from file base name */
  const char *base = sep ? sep + 1 : mainObcPath;
  char name[64];
  strncpy(name, base, 63);
  char *dot = strrchr(name, '.');
  if (dot) *dot = 0;
  loadMod(vm, name, dir, &tagCounter);
  vm->running = 1;
  vm->haltCode = 0;
  return vm;
}

/* ---------- builtins ---------- */
void callBuiltin(VM *vm, int id, int base, int nparams) {
  Cell *arg = &vm->stack[base];
  if (id >= 60) { if (sqliteBuiltin(vm, id, arg, base)) return; }
  switch (id) {
    case 0: /* Out.Int(x, w) */
      printf("%*d", (int)(int32_t)arg[1], (int)(int32_t)arg[0]);
      break;
    case 1: /* Out.Real(x, w) */
      printf("%*g", (int)(int32_t)arg[1], cellToDouble(arg[0]));
      break;
    case 2: /* Out.Char(c) */
      putchar((int)(int32_t)arg[0]);
      break;
    case 3: { /* Out.String(s) */
      Cell ref = arg[0];
      if (ref == 0) break;
      int ndim = (int)-vm->heap[ref];
      int total = (int)vm->heap[ref + ndim + 1];
      int hdr = ndim + 2;
      for (int i = 0; i < total; i++) {
        Cell c = vm->heap[ref + hdr + i];
        if (c == 0) break;
        putchar((int)c);
      }
      break;
    }
    case 4: /* Out.Ln */
      putchar('\n');
      break;
    case 5: { /* In.Int(VAR x) */
      int v = 0;
      if (scanf("%d", &v) != 1) v = 0;
      memWrite(vm, arg[0], v);
      break;
    }
    case 6: { /* In.Real(VAR x) */
      double d = 0;
      if (scanf("%lf", &d) != 1) d = 0;
      memWrite(vm, arg[0], cellFromDouble(d));
      break;
    }
    case 7: { /* In.Char(VAR c) */
      int c;
      do { c = getchar(); } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');
      if (c == EOF) c = 0;
      memWrite(vm, arg[0], c);
      break;
    }
    case 8: { /* In.Line(VAR s) : s is array of char; arg is slot addr */
      Cell slotAddr = arg[0];
      Cell ref = memRead(vm, slotAddr);
      int ndim = (int)-vm->heap[ref];
      int total = (int)vm->heap[ref + ndim + 1];
      int hdr = ndim + 2;
      char buf[4096];
      int c;
      do { c = getchar(); } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');
      if (c == EOF) buf[0] = 0;
      else { ungetc(c, stdin); if (!fgets(buf, sizeof buf, stdin)) buf[0] = 0; }
      int n = (int)strlen(buf);
      while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = 0;
      if (n > total - 1) n = total - 1;
      for (int i = 0; i < n; i++) vm->heap[ref + hdr + i] = (unsigned char)buf[i];
      vm->heap[ref + hdr + n] = 0;
      break;
    }
    case 9: /* HALT(n) */
      vm->haltCode = (int)(int32_t)arg[0];
      vm->running = 0;
      break;
    case 10: /* Out.Long(x, w) */
      printf("%*lld", (int)(int32_t)arg[1], (long long)(int64_t)arg[0]);
      break;
    case 11: /* Out.Byte(b) : raw byte to stdout */
      fputc((int)((int32_t)arg[0] & 0xFF), stdout);
      break;
    case 12: { /* In.Byte(VAR b) : raw byte from stdin, -1 at EOF */
      int c = getchar();
      memWrite(vm, arg[0], c == EOF ? -1 : c);
      break;
    }
    case 20: { /* Files.Open(name): File or NIL */
      char nm[1024];
      refToStr(vm, arg[0], nm, sizeof nm);
      FILE *fp = fopen(nm, "rb");
      vm->stack[base] = fp ? fileAlloc(vm, fp) : 0;
      break;
    }
    case 21: { /* Files.Create(name): File or NIL */
      char nm[1024];
      refToStr(vm, arg[0], nm, sizeof nm);
      FILE *fp = fopen(nm, "wb");
      vm->stack[base] = fp ? fileAlloc(vm, fp) : 0;
      break;
    }
    case 22: { /* Files.Close(f) */
      FILE *fp = fileOf(vm, arg[0]);
      if (fp) {
        int handle = (int)vm->heap[arg[0] + 2];
        fclose(fp);
        fileTab[handle - 1] = NULL;
      }
      break;
    }
    case 23: { /* Files.ReadByte(f): INTEGER, -1 at EOF */
      FILE *fp = fileOf(vm, arg[0]);
      int c = fp ? fgetc(fp) : EOF;
      if (c == EOF) vm->heap[arg[0] + 3] = 1;
      vm->stack[base] = c == EOF ? -1 : c;
      break;
    }
    case 24: /* Files.WriteByte(f, b) */
      if (fileOf(vm, arg[0])) fputc((int)(int32_t)arg[1] & 0xFF, fileOf(vm, arg[0]));
      break;
    case 25: { /* Files.Read(f, buf, len): INTEGER count — one char per heap cell */
      FILE *fp = fileOf(vm, arg[0]);
      Cell ref = arg[1];
      int len = (int)(int32_t)arg[2];
      int n = 0;
      if (fp && ref) {
        int ndim = (int)-vm->heap[ref];
        int total = (int)vm->heap[ref + ndim + 1];
        int hdr = ndim + 2;
        if (len > total) len = total;
        for (int i = 0; i < len; i++) {
          int c = fgetc(fp);
          if (c == EOF) { vm->heap[arg[0] + 3] = 1; break; }
          vm->heap[ref + hdr + i] = c;
          n++;
        }
      }
      vm->stack[base] = n;
      break;
    }
    case 26: { /* Files.Write(f, buf, len) — one char per heap cell */
      FILE *fp = fileOf(vm, arg[0]);
      Cell ref = arg[1];
      int len = (int)(int32_t)arg[2];
      if (fp && ref) {
        int ndim = (int)-vm->heap[ref];
        int total = (int)vm->heap[ref + ndim + 1];
        int hdr = ndim + 2;
        if (len > total) len = total;
        for (int i = 0; i < len; i++)
          fputc((int)(vm->heap[ref + hdr + i] & 0xFF), fp);
      }
      break;
    }
    case 27: { /* Files.Eof(f): BOOLEAN */
      FILE *fp = fileOf(vm, arg[0]);
      int e = fp ? (vm->heap[arg[0] + 3] || feof(fp)) : 1;
      vm->stack[base] = e;
      break;
    }
    case 28: { /* Files.Length(f): LONGINT */
      FILE *fp = fileOf(vm, arg[0]);
      long len = 0;
      if (fp) {
        long cur = ftell(fp);
        fseek(fp, 0, SEEK_END);
        len = ftell(fp);
        fseek(fp, cur, SEEK_SET);
      }
      vm->stack[base] = len;
      break;
    }
    case 29: { /* Files.Pos(f): LONGINT */
      FILE *fp = fileOf(vm, arg[0]);
      vm->stack[base] = fp ? ftell(fp) : 0;
      break;
    }
    case 30: { /* Files.Set(f, pos) */
      FILE *fp = fileOf(vm, arg[0]);
      if (fp) fseek(fp, (long)(int64_t)arg[1], SEEK_SET);
      break;
    }
    case 31: { /* Files.Delete(name): BOOLEAN */
      char nm[1024];
      refToStr(vm, arg[0], nm, sizeof nm);
      vm->stack[base] = remove(nm) == 0;
      break;
    }
    case 32: { /* Files.Exists(name): BOOLEAN */
      char nm[1024];
      refToStr(vm, arg[0], nm, sizeof nm);
      FILE *fp = fopen(nm, "rb");
      if (fp) fclose(fp);
      vm->stack[base] = fp != NULL;
      break;
    }
    case 40: /* SYSTEM.BAND(a, b): LONGINT */
      vm->stack[base] = (Cell)((int64_t)arg[0] & (int64_t)arg[1]);
      break;
    case 41: /* SYSTEM.BOR(a, b): LONGINT */
      vm->stack[base] = (Cell)((int64_t)arg[0] | (int64_t)arg[1]);
      break;
    case 42: /* SYSTEM.BXOR(a, b): LONGINT */
      vm->stack[base] = (Cell)((int64_t)arg[0] ^ (int64_t)arg[1]);
      break;
    case 43: /* SYSTEM.BNOT(a): LONGINT */
      vm->stack[base] = (Cell)(~(int64_t)arg[0]);
      break;
    case 44: { /* SYSTEM.LSH(x, n): shift left if n>=0, logical right if n<0 */
      uint64_t u = (uint64_t)(int64_t)arg[0];
      int n = (int)(int32_t)arg[1];
      uint64_t r = (n >= 0) ? (u << (n & 63)) : (u >> ((-n) & 63));
      vm->stack[base] = (Cell)(int64_t)r;
      break;
    }
    case 45: { /* SYSTEM.ROT(x, n): rotate left by n mod 64 (negative n -> right) */
      uint64_t u = (uint64_t)(int64_t)arg[0];
      int n = (int)(int32_t)arg[1] & 63;
      uint64_t r = (u << n) | (u >> ((64 - n) & 63));
      vm->stack[base] = (Cell)(int64_t)r;
      break;
    }
    case 46: { /* SYSTEM.BIT(x, n): BOOLEAN */
      int n = (int)(int32_t)arg[1] & 63;
      vm->stack[base] = ((int64_t)arg[0] >> n) & 1;
      break;
    }
    case 47: /* SYSTEM.ARGC: INTEGER (program args, after the .obc path) */
      vm->stack[base] = sysArgc;
      break;
    case 48: { /* SYSTEM.ARGV(i, VAR s): copy program arg i into char array s */
      Cell slotAddr = arg[1];
      Cell ref = memRead(vm, slotAddr);
      if (!ref) vmRuntimeError(vm, "ARGV: NIL array");
      int ndim = (int)-vm->heap[ref];
      int total = (int)vm->heap[ref + ndim + 1];
      int hdr = ndim + 2;
      int i = (int)(int32_t)arg[0];
      const char *s = (sysArgv && i >= 0 && i < sysArgc) ? sysArgv[i] : "";
      int n = (int)strlen(s);
      if (n > total - 1) n = total - 1;
      for (int k = 0; k < n; k++) vm->heap[ref + hdr + k] = (unsigned char)s[k];
      vm->heap[ref + hdr + n] = 0;
      break;
    }
    case 49: /* SYSTEM.TICKS: LONGINT, milliseconds */
      vm->stack[base] = (Cell)(int64_t)((int64_t)clock() * 1000 / CLOCKS_PER_SEC);
      break;
    case 50: /* SYSTEM.EXIT(code) */
      vm->haltCode = (int)(int32_t)arg[0];
      vm->running = 0;
      break;
    case 51: /* SYSTEM.L2I(x: LONGINT): INTEGER — truncate to 32 bits */
      vm->stack[base] = (Cell)(int32_t)(int64_t)arg[0];
      break;
    case 52: /* SYSTEM.REALBITS(x: REAL): LONGINT — a REAL cell already holds the double bits */
      vm->stack[base] = arg[0];
      break;
    case 53: /* SYSTEM.BITSREAL(b: LONGINT): REAL — identity at cell level */
      vm->stack[base] = arg[0];
      break;
    case 54: /* SYSTEM.I2REAL(x: INTEGER): REAL */
      vm->stack[base] = cellFromDouble((double)(int32_t)arg[0]);
      break;
    default:
      vmRuntimeError(vm, "unknown builtin");
  }
  (void)nparams;
}

/* ---------- floored division ---------- */
void idivmod(Cell a, Cell b, Cell *q, Cell *r) {
  if (b == 0) { *q = 0; *r = 0; return; } /* caller checks */
  Cell qq = a / b, rr = a % b;
  if (rr != 0 && ((rr < 0) != (b < 0))) { qq -= 1; rr += b; }
  *q = qq; *r = rr;
}


int builtinHasResult(int id) {
  switch (id) {
    case 20: case 21: case 23: case 25: case 27:
    case 28: case 29: case 31: case 32:
    case 40: case 41: case 42: case 43: case 44: case 45: case 46:
    case 47: case 49:
    case 51: case 52: case 53: case 54:
    case 60: case 62: case 63: case 64: case 65: case 67: case 68: /* SQLite w/ result */
      return 1;
  }
  return 0;
}

int builtinNparams(int id) {
  switch (id) {
    case 0: case 1: return 2;   /* Out.Int, Out.Real */
    case 2: case 3: return 1;   /* Out.Char, Out.String */
    case 4: return 0;           /* Out.Ln */
    case 5: case 6: case 7: case 8: return 1; /* In.* */
    case 9: return 1;           /* HALT */
    case 10: return 2;          /* Out.Long */
    case 11: return 1;          /* Out.Byte */
    case 12: return 1;          /* In.Byte */
    case 20: case 21: return 1; /* Files.Open/Create */
    case 22: case 23: case 27: case 28: case 29: return 1;
    case 24: case 30: return 2; /* WriteByte, Set */
    case 25: case 26: return 3; /* Read, Write */
    case 31: case 32: return 1; /* Delete, Exists */
    case 40: case 41: case 42: case 44: case 45: case 46: case 48: return 2; /* SYSTEM */
    case 43: case 50: case 51: case 52: case 53: case 54: return 1; /* BNOT, EXIT, casts */
    case 60: case 62: case 65: case 67: return 2;         /* SQLite Open/Exec/ColumnInt/ColumnDouble */
    case 61: case 64: case 68: case 69: return 1;         /* Close/Step/ColumnCount/Finalize */
    case 63: case 66: return 3;                           /* Prepare/ColumnText */
    case 70: return 2;                                    /* Errmsg */
    /* 47 (ARGC), 49 (TICKS): 0 params -> default */
  }
  return 0;
}

/* ---------- driver ---------- */
void rtEnterBody(VM *vm) {
  /* initial frame: module 0, proc 0 (body) */
  VMMod *main = vm->mods[0];
  Frame *f0 = &vm->frames[0];
  f0->mod = 0; f0->proc = 0; f0->pc = 0; f0->base = 0; f0->slink = -1;
  f0->extra = 0; f0->cref = 0;
  vm->fp = 1;
  vm->sp = main->lm->procs[0].nlocals;
}
