MODULE VM;
(* VM.Mod — the Oberon-07 virtual machine written in Oberon itself
   (étape 4 of docs/AUTOHEBERGEMENT.md).

   It loads a .obc file (given as program argument 0) and interprets it:
     stage-0 VM:      bootstrap/obvm.exe VM.obc <prog.obc> [args...]
     native (étape 5): bootstrap/ob2c.exe VM.obc -o VM.c && gcc -O2 -Ibootstrap/src VM.c \
                       bootstrap/src/rt.c bootstrap/src/ob.c bootstrap/src/model.c bootstrap/src/module.c -lm

   The opcode numbers below are generated from bootstrap/src/ob.h and the
   builtin ids from bootstrap/src/parser.c — keep them in sync. *)

IMPORT Out, In, Files, SYSTEM;

CONST
  (* --- opcodes (generated from bootstrap/src/ob.h) --- *)
  OP_NOP = 0; OP_CONST_I = 1; OP_CONST_R = 2; OP_CONST_S = 3;
  OP_LOAD_LOCAL = 4; OP_STORE_LOCAL = 5; OP_ADDR_LOCAL = 6;
  OP_LOAD_GLOBAL = 7; OP_STORE_GLOBAL = 8; OP_ADDR_GLOBAL = 9;
  OP_LOAD_AT = 10; OP_STORE_AT = 11; OP_TO_ADDR = 12;
  OP_IADD = 13; OP_ISUB = 14; OP_IMUL = 15; OP_IDIV = 16; OP_IMOD = 17;
  OP_INEG = 18; OP_IABS = 19; OP_IODD = 20;
  OP_FADD = 21; OP_FSUB = 22; OP_FMUL = 23; OP_FDIV = 24; OP_FNEG = 25; OP_FABS = 26; OP_FFLOOR = 27;
  OP_I2F = 28; OP_F2I = 29;
  OP_ILT = 30; OP_ILE = 31; OP_IGT = 32; OP_IGE = 33; OP_IEQ = 34; OP_INE = 35;
  OP_FLT = 36; OP_FLE = 37; OP_FGT = 38; OP_FGE = 39; OP_FEQ = 40; OP_FNE = 41;
  OP_EQ = 42; OP_NE = 43; OP_AND = 44; OP_OR = 45; OP_NOT = 46;
  OP_SET_UNION = 47; OP_SET_DIFF = 48; OP_SET_INTER = 49; OP_SET_MEMBER = 50;
  OP_JMP = 51; OP_JZ = 52; OP_JNZ = 53; OP_CALL = 54; OP_RET = 55;
  OP_NEW = 56; OP_ALLOC_ARRAY = 57; OP_LEN = 58; OP_ISTYPE = 59; OP_CHECKTYPE = 60;
  OP_ELEM_ADDR = 61; OP_COPY = 62; OP_COPY_STR = 63;
  OP_DUP = 64; OP_DROP = 65; OP_SWAP = 66; OP_SHL = 67; OP_SHR = 68; OP_AADD = 69;
  OP_CONST_L = 70;
  OP_LADD = 71; OP_LSUB = 72; OP_LMUL = 73; OP_LDIV = 74; OP_LMOD = 75;
  OP_LNEG = 76; OP_LABS = 77; OP_LODD = 78;
  OP_LLT = 79; OP_LLE = 80; OP_LGT = 81; OP_LGE = 82; OP_LEQ = 83; OP_LNE = 84; OP_L2I = 85;
  OP_JUMPTABLE = 86;
  OP_DISPOSE = 87;
  OP_PROCVAL = 88; OP_CALLP = 89; OP_COUNT = 90;

  TAG_PROC = 3;                       (* top byte of a procedure-value cell *)
  SHIFT56 = 72057594037927936;        (* 2^56 *)
  SHIFT48 = 281474976710656;          (* 2^48 *)

  (* --- builtin proc ids (bootstrap/src/parser.c), module id 255 --- *)
  B_OUT_INT = 0; B_OUT_REAL = 1; B_OUT_CHAR = 2; B_OUT_STRING = 3; B_OUT_LN = 4;
  B_IN_INT = 5; B_IN_REAL = 6; B_IN_CHAR = 7; B_IN_LINE = 8; B_HALT = 9;
  B_OUT_LONG = 10; B_OUT_BYTE = 11; B_IN_BYTE = 12;
  B_FILES_OPEN = 20; B_FILES_CREATE = 21; B_FILES_CLOSE = 22; B_FILES_READBYTE = 23;
  B_FILES_WRITEBYTE = 24; B_FILES_READ = 25; B_FILES_WRITE = 26; B_FILES_EOF = 27;
  B_FILES_LENGTH = 28; B_FILES_POS = 29; B_FILES_SET = 30; B_FILES_DELETE = 31; B_FILES_EXISTS = 32;
  B_SYS_BAND = 40; B_SYS_BOR = 41; B_SYS_BXOR = 42; B_SYS_BNOT = 43;
  B_SYS_LSH = 44; B_SYS_ROT = 45; B_SYS_BIT = 46; B_SYS_ARGC = 47; B_SYS_ARGV = 48;
  B_SYS_TICKS = 49; B_SYS_EXIT = 50; B_SYS_L2I = 51; B_SYS_REALBITS = 52; B_SYS_BITSREAL = 53; B_SYS_I2REAL = 54;

  (* --- type kinds (bootstrap/src/model.h) --- *)
  TK_ARRAY = 7; TK_RECORD = 8; TK_POINTER = 9; TK_LONGINT = 10; TK_PROC = 11;

  FILE_TAG = 1073741824;  (* 0x40000000: reserved runtime tag for Files.FileDesc *)
  CLOSURE_TAG = 1073741825; (* 0x40000001: heap tag of closure objects *)
  MASK32 = 4294967295;    (* 0xFFFFFFFF *)
  MASK48 = 281474976710655;   (* 0xFFFFFFFFFFFF *)
  MASK56 = 72057594037927935; (* 0x00FFFFFFFFFFFFFF *)
  SIGN32 = 2147483648;

  MAXMOD = 32; MAXPROC = 64; MAXTYPE = 96; MAXSTR = 256; MAXDIM = 8; MAXGLOB = 256;
  HEAPSIZE = 1048576; STACKSIZE = 65536; CODESIZE = 2097152; BUFSIZE = 1048576; GLOBSIZE = 262144; FRAMES = 256;

VAR
  (* ---- guest memory ---- *)
  heap: ARRAY HEAPSIZE OF LONGINT; heapUsed: INTEGER; freeHead: INTEGER;
  stack: ARRAY STACKSIZE OF LONGINT; sp: INTEGER;
  fmod, fproc, fpc, fbase, fslink: ARRAY FRAMES OF INTEGER;
  fextra, fcref: ARRAY FRAMES OF INTEGER;  (* closure support: extra frames to pop / closure object ref *)
  scratch: ARRAY 256 OF INTEGER;           (* scratch for closure materialization *)
  fp: INTEGER; running: BOOLEAN; haltCode: INTEGER;
  code: ARRAY CODESIZE OF LONGINT; codeUsed: INTEGER;   (* guest bytecode pool, one byte per cell *)
  globals: ARRAY GLOBSIZE OF LONGINT; globalsUsed: INTEGER;
  (* ---- per-module tables ---- *)
  nmods: INTEGER;
  modName: ARRAY MAXMOD, 64 OF CHAR;
  map: ARRAY MAXMOD, MAXMOD OF INTEGER;                  (* map[g][localMod] -> gid *)
  gbase, gsize: ARRAY MAXMOD OF INTEGER;
  ntypes: ARRAY MAXMOD OF INTEGER;
  tkind, tbase, tto, tpayload, tndim, ttotal: ARRAY MAXMOD, MAXTYPE OF INTEGER;
  telem: ARRAY MAXMOD, MAXTYPE OF INTEGER;  (* array elem type idx *)
  tdims: ARRAY MAXMOD, MAXTYPE, MAXDIM OF INTEGER;
  rtTag, rtPtrTag, rtPtrSize: ARRAY MAXMOD, MAXTYPE OF INTEGER;
  (* ---- per-proc tables ---- *)
  pnparams, pnlocals, phasResult, pcofs, pclen: ARRAY MAXMOD, MAXPROC OF INTEGER;
  strRefs: ARRAY MAXMOD, MAXSTR OF INTEGER;
  vmTagBase: ARRAY 1024 OF INTEGER; tagCounter: INTEGER;
  fileTab: ARRAY 256 OF Files.File;                      (* guest Files: handle = index+1 *)
  hostArgc: INTEGER;
  (* ---- .obc reading ---- *)
  fbuf: ARRAY BUFSIZE OF LONGINT; flen, fcur: INTEGER;
  (* ---- scratch ---- *)
  path, dir, name, msgbuf, dir2: ARRAY 256 OF CHAR; tname: ARRAY 256 OF CHAR;
  gOff, gTidx, gExp: ARRAY MAXGLOB OF INTEGER; gNg: INTEGER;
  impNames: ARRAY MAXMOD, 256 OF CHAR; impCount: INTEGER;  (* deferred imports (fbuf is shared) *)

(* ---------- errors ---------- *)
TYPE Handler = PROCEDURE();
VAR handlers: ARRAY OP_COUNT OF Handler;
VAR op, pc, cur, cofs, oldfp, slot, fi, ld, off, lmod, pidx, steps, base: INTEGER;
    g, st, n, i, tag, hres, ok, to, ref: INTEGER;
    e, cr, jb, cf, nl, capBase, bi, bas, prev, k, j, total: INTEGER;
    u, a, b, rv, t, tg: LONGINT; x, y: REAL;

(* operand byte length per opcode (for threaded-code translation at load) *)
PROCEDURE OpLen(op: INTEGER): INTEGER;
BEGIN
  CASE op OF
    OP_CONST_I, OP_CONST_S, OP_LOAD_LOCAL, OP_STORE_LOCAL, OP_ADDR_LOCAL, OP_LEN, OP_COPY,
    OP_JMP, OP_JZ, OP_JNZ: RETURN 4
  | OP_CONST_R, OP_CONST_L: RETURN 8
  | OP_LOAD_GLOBAL, OP_STORE_GLOBAL, OP_ADDR_GLOBAL, OP_NEW, OP_ALLOC_ARRAY,
    OP_ISTYPE, OP_CHECKTYPE, OP_DISPOSE: RETURN 5
  | OP_CALL, OP_PROCVAL: RETURN 12
  ELSE RETURN 0
  END
END OpLen;

PROCEDURE Fatal;
BEGIN Out.String("vm: "); Out.String(msgbuf); Out.Ln; SYSTEM.EXIT(1)
END;

(* ---------- guest stack ---------- *)
PROCEDURE Push(v: LONGINT);
BEGIN
  IF sp >= STACKSIZE THEN msgbuf := "stack overflow"; Fatal END;
  stack[sp] := v; INC(sp)
END;

PROCEDURE Pop(): LONGINT;
BEGIN DEC(sp); RETURN stack[sp] END;

(* sign-extend / wrap a LONGINT to a 32-bit integer value (as a LONGINT cell) *)
PROCEDURE ToI32(x: LONGINT): LONGINT;
VAR r: LONGINT;
BEGIN r := SYSTEM.BAND(x, MASK32); IF r >= SIGN32 THEN r := r - MASK32 - 1 END; RETURN r
END;

(* ---------- guest heap ---------- *)
(* first-fit on the free list, else bump. Free block: heap[h]=0, heap[h+1]=size, heap[h+2]=next *)
PROCEDURE HeapAlloc(n: INTEGER): INTEGER;
VAR h, i, prev, cur, size, next, rem: INTEGER;
BEGIN
  prev := 0; cur := freeHead;
  WHILE cur # 0 DO
    size := SYSTEM.L2I(heap[cur+1]);
    IF size >= n THEN
      next := SYSTEM.L2I(heap[cur+2]);
      IF size - n >= 4 THEN (* split: remainder stays free where the block was *)
        rem := cur + n;
        heap[rem] := 0; heap[rem+1] := size - n; heap[rem+2] := next;
        IF prev = 0 THEN freeHead := rem ELSE heap[prev+2] := rem END
      ELSE
        IF prev = 0 THEN freeHead := next ELSE heap[prev+2] := next END
      END;
      h := cur;
      FOR i := 0 TO n-1 DO heap[h+i] := 0 END;
      RETURN h
    END;
    prev := cur; cur := SYSTEM.L2I(heap[cur+2])
  END;
  IF heapUsed + n > HEAPSIZE THEN msgbuf := "heap overflow"; Fatal END;
  h := heapUsed; heapUsed := heapUsed + n;
  FOR i := 0 TO n-1 DO heap[h+i] := 0 END;
  RETURN h
END;

PROCEDURE HeapFree(ref, size: INTEGER);
BEGIN
  IF (ref <= 0) OR (size < 3) THEN msgbuf := "bad free"; Fatal END;
  IF heap[ref] = 0 THEN msgbuf := "double DISPOSE"; Fatal END;
  heap[ref] := 0; heap[ref+1] := size; heap[ref+2] := freeHead; freeHead := ref
END;

(* cells per array element: record elements are stored inline (payload), others 1 cell *)
PROCEDURE ElemCells(gid, t: INTEGER): INTEGER;
BEGIN
  IF (telem[gid, t] >= 0) & (tkind[gid, telem[gid, t]] = TK_RECORD) THEN
    RETURN tpayload[gid, telem[gid, t]]
  END;
  RETURN 1
END ElemCells;

PROCEDURE ObjSize(gid, t: INTEGER): INTEGER;
BEGIN
  IF tkind[gid, t] = TK_ARRAY THEN RETURN tndim[gid, t] + 2 + ttotal[gid, t] * ElemCells(gid, t) END;
  IF tkind[gid, t] = TK_RECORD THEN RETURN 2 + tpayload[gid, t] END;
  RETURN 0
END;

PROCEDURE AllocArray(gid, t: INTEGER): INTEGER;
VAR h, nd, tot, i: INTEGER;
BEGIN
  nd := tndim[gid, t]; tot := ttotal[gid, t] * ElemCells(gid, t); (* header total = cell count *)
  h := HeapAlloc(nd + 2 + tot);
  heap[h] := -nd;
  FOR i := 0 TO nd-1 DO heap[h+1+i] := tdims[gid, t, i] END;
  heap[h+nd+1] := tot;
  RETURN h
END;

PROCEDURE AllocString(VAR s: ARRAY 256 OF CHAR): INTEGER;
VAR h, i, len: INTEGER;
BEGIN
  len := 0; WHILE s[len] # 0X DO INC(len) END;
  h := HeapAlloc(3 + len + 1);
  heap[h] := -1; heap[h+1] := len+1; heap[h+2] := len+1;
  FOR i := 0 TO len-1 DO heap[h+3+i] := ORD(s[i]) END;
  heap[h+3+len] := 0;
  RETURN h
END;

(* ---------- tagged memory ---------- *)
PROCEDURE MemRead(a: LONGINT): LONGINT;
VAR tag, lmod, off, g, z: LONGINT;
BEGIN
  tag := SYSTEM.LSH(a, -56);
  IF tag = 0 THEN RETURN stack[SYSTEM.L2I(SYSTEM.BAND(a, MASK56))]
  ELSIF tag = 1 THEN
    g := SYSTEM.BAND(SYSTEM.LSH(a, -48), 255); (* absolute gid, resolved at ADDR_GLOBAL *)
    off := SYSTEM.BAND(a, MASK48);
    RETURN globals[gbase[SYSTEM.L2I(g)] + SYSTEM.L2I(off)]
  ELSIF tag = 2 THEN RETURN heap[SYSTEM.L2I(SYSTEM.BAND(a, MASK56))]
  ELSE msgbuf := "bad address"; Fatal; z := 0; RETURN z
  END
END;

PROCEDURE MemWrite(a: LONGINT; v: LONGINT);
VAR tag, lmod, off, g, z: LONGINT;
BEGIN
  tag := SYSTEM.LSH(a, -56);
  IF tag = 0 THEN stack[SYSTEM.L2I(SYSTEM.BAND(a, MASK56))] := v
  ELSIF tag = 1 THEN
    g := SYSTEM.BAND(SYSTEM.LSH(a, -48), 255); (* absolute gid, resolved at ADDR_GLOBAL *)
    off := SYSTEM.BAND(a, MASK48);
    globals[gbase[SYSTEM.L2I(g)] + SYSTEM.L2I(off)] := v
  ELSIF tag = 2 THEN heap[SYSTEM.L2I(SYSTEM.BAND(a, MASK56))] := v
  ELSE msgbuf := "bad address"; Fatal
  END
END;

(* ---------- guest Files ---------- *)
PROCEDURE RefToStr(ref: LONGINT; VAR buf: ARRAY 256 OF CHAR);
VAR ndim, total, i, n, r: INTEGER;
BEGIN
  n := 0;
  IF ref # 0 THEN
    r := SYSTEM.L2I(ref);
    ndim := -SYSTEM.L2I(heap[r]); total := SYSTEM.L2I(heap[r+ndim+1]);
    i := 0;
    WHILE i < total DO
      IF (i >= LEN(buf, 0) - 1) OR (heap[r+ndim+2+i] = 0) THEN i := total
      ELSE buf[i] := CHR(SYSTEM.L2I(heap[r+ndim+2+i])); INC(i) END
    END;
    n := i
  END;
  buf[n] := 0X
END;

PROCEDURE FileAlloc(hf: Files.File): INTEGER;
VAR i, h: INTEGER;
BEGIN
  FOR i := 0 TO 255 DO
    IF fileTab[i] = NIL THEN
      fileTab[i] := hf;
      h := HeapAlloc(4);
      heap[h] := FILE_TAG; heap[h+1] := 2; heap[h+2] := i+1; heap[h+3] := 0;
      RETURN h
    END
  END;
  Files.Close(hf);
  RETURN 0
END;

(* guest File ref -> handle (index+1), 0 = invalid *)
PROCEDURE FileHandle(ref: LONGINT): INTEGER;
VAR r: INTEGER;
BEGIN
  IF ref = 0 THEN RETURN 0 END;
  r := SYSTEM.L2I(ref);
  IF heap[r] # FILE_TAG THEN RETURN 0 END;
  RETURN SYSTEM.L2I(heap[r+2])
END;

(* ---------- .obc reading (whole file in fbuf, cursor fcur) ---------- *)
PROCEDURE RU8(): INTEGER;
VAR b: INTEGER;
BEGIN b := SYSTEM.L2I(fbuf[fcur]); INC(fcur); RETURN b END;

PROCEDURE RU32(): LONGINT;
VAR v: LONGINT;
BEGIN
  v := RU8(); v := v + RU8()*256; v := v + RU8()*65536; v := v + RU8()*16777216; RETURN v
END;

PROCEDURE RU64(): LONGINT;
VAR v: LONGINT;
BEGIN
  v := RU8(); v := v + RU8()*256; v := v + RU8()*65536; v := v + RU8()*16777216;
  v := v + RU8()*4294967296; v := v + RU8()*1099511627776;
  v := v + RU8()*281474976710656; v := v + RU8()*72057594037927936; RETURN v
END;

PROCEDURE RStr(VAR buf: ARRAY 256 OF CHAR);
VAR n, i: INTEGER;
BEGIN
  n := SYSTEM.L2I(RU32());
  IF n > LEN(buf, 0) - 1 THEN n := LEN(buf, 0) - 1 END;
  FOR i := 0 TO n-1 DO buf[i] := CHR(RU8()) END;
  buf[n] := 0X
END;

PROCEDURE ReadFile(VAR p: ARRAY 256 OF CHAR);
VAR f: Files.File; b: INTEGER;
BEGIN
  f := Files.Open(p);
  IF f = NIL THEN Out.String("vm: cannot open "); Out.String(p); Out.Ln; SYSTEM.EXIT(1) END;
  flen := 0;
  b := Files.ReadByte(f);
  WHILE b >= 0 DO
    IF flen >= BUFSIZE THEN msgbuf := "file too large"; Fatal END;
    fbuf[flen] := b; INC(flen);
    b := Files.ReadByte(f)
  END;
  Files.Close(f);
  fcur := 0
END;

(* path := d + "/" + nm + ".obc" *)
PROCEDURE MkPath(VAR d, nm: ARRAY 256 OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE d[i] # 0X DO path[i] := d[i]; INC(i) END;
  path[i] := CHR(47); INC(i);
  j := 0; WHILE nm[j] # 0X DO path[i] := nm[j]; INC(i); INC(j) END;
  path[i] := CHR(46); INC(i); path[i] := 'o'; INC(i); path[i] := 'b'; INC(i); path[i] := 'c'; INC(i); path[i] := 0X
END;

(* out := d + rel *)
PROCEDURE CatDir(VAR d, out: ARRAY 256 OF CHAR; rel: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE d[i] # 0X DO out[i] := d[i]; INC(i) END;
  j := 0; WHILE rel[j] # 0X DO out[i] := rel[j]; INC(i); INC(j) END;
  out[i] := 0X
END;

PROCEDURE TryDir(VAR d, nm: ARRAY 256 OF CHAR): BOOLEAN;
BEGIN
  MkPath(d, nm);
  IF Files.Exists(path) THEN ReadFile(path); RETURN TRUE END;
  RETURN FALSE
END;

(* ---------- module loading ---------- *)
PROCEDURE FindMod(VAR nm: ARRAY 256 OF CHAR): INTEGER;
VAR g, i: INTEGER;
BEGIN
  g := 0;
  WHILE g < nmods DO
    i := 0;
    WHILE (i < 63) & (modName[g, i] = nm[i]) & (nm[i] # 0X) DO INC(i) END;
    IF modName[g, i] = nm[i] THEN RETURN g END;
    INC(g)
  END;
  RETURN -1
END;

PROCEDURE LoadMod(VAR nm: ARRAY 256 OF CHAR; VAR d: ARRAY 256 OF CHAR): INTEGER;
VAR gid, i, j, k, n, nt, np, ns, b, npar, nloc, clen: INTEGER; v: LONGINT;
BEGIN
  gid := FindMod(nm);
  IF gid >= 0 THEN RETURN gid END;
  IF nmods >= MAXMOD THEN msgbuf := "too many modules"; Fatal END;
  gid := nmods; INC(nmods);
  i := 0; WHILE (i < 63) & (nm[i] # 0X) DO modName[gid, i] := nm[i]; INC(i) END; modName[gid, i] := 0X;
  (* search path: d, then d/../lib, then d/../../lib (project lib/) *)
  IF TryDir(d, nm) THEN
  ELSE
    CatDir(d, dir2, "/../lib");
    IF TryDir(dir2, nm) THEN
    ELSE
      CatDir(d, dir2, "/../../lib");
      IF ~TryDir(dir2, nm) THEN
        Out.String("vm: cannot open "); Out.String(nm); Out.Ln; SYSTEM.EXIT(1)
      END
    END
  END;
  (* magic "OBC7" + version 1 *)
  IF (RU8() # 79) OR (RU8() # 66) OR (RU8() # 67) OR (RU8() # 55) OR (RU32() # 1) THEN
    msgbuf := "bad .obc file"; Fatal
  END;
  RStr(tname); (* module name *)
  n := SYSTEM.L2I(RU32()); (* nimports *)
  IF n >= MAXMOD THEN msgbuf := "too many imports"; Fatal END;
  map[gid, 0] := gid;
  (* collect import names now; load them AFTER this module is fully parsed,
     because the recursive LoadMod reuses the shared file buffer fbuf *)
  impCount := n;
  FOR i := 0 TO n-1 DO
    RStr(tname);
    j := 0; WHILE (j < 255) & (tname[j] # 0X) DO impNames[i, j] := tname[j]; INC(j) END;
    impNames[i, j] := 0X
  END;
  (* globals section: remember; array allocation after types are known *)
  gsize[gid] := SYSTEM.L2I(RU32());
  IF globalsUsed + gsize[gid] > GLOBSIZE THEN msgbuf := "globals overflow"; Fatal END;
  gbase[gid] := globalsUsed; globalsUsed := globalsUsed + gsize[gid];
  gNg := SYSTEM.L2I(RU32());
  IF gNg > MAXGLOB THEN msgbuf := "too many globals"; Fatal END;
  FOR i := 0 TO gNg-1 DO
    RStr(tname); gOff[i] := SYSTEM.L2I(RU32()); gTidx[i] := SYSTEM.L2I(RU32()); gExp[i] := RU8()
  END;
  (* types *)
  nt := SYSTEM.L2I(RU32());
  IF nt > MAXTYPE THEN msgbuf := "too many types"; Fatal END;
  ntypes[gid] := nt;
  FOR k := 0 TO nt-1 DO
    j := RU8(); RStr(tname); RU8(); (* kind, name, exported *)
    tkind[gid, k] := j; tbase[gid, k] := -1; tto[gid, k] := -1; telem[gid, k] := -1;
    tpayload[gid, k] := 0; tndim[gid, k] := 0; ttotal[gid, k] := 1;
    IF j = TK_ARRAY THEN
      n := SYSTEM.L2I(RU32());
      IF n < 0 THEN (* 0xFFFFFFFF sentinel: open array param "ARRAY OF T", no dims *)
        n := 1; tndim[gid, k] := 1; tdims[gid, k, 0] := 1073741823; ttotal[gid, k] := 1073741823
      ELSE
        IF n > MAXDIM THEN msgbuf := "too many array dims"; Fatal END;
        tndim[gid, k] := n;
        v := 1;
        FOR i := 0 TO n-1 DO tdims[gid, k, i] := SYSTEM.L2I(RU32()); v := v * tdims[gid, k, i] END;
        ttotal[gid, k] := SYSTEM.L2I(v)
      END;
      telem[gid, k] := SYSTEM.L2I(RU32()) (* elem type *)
    ELSIF j = TK_RECORD THEN
      tpayload[gid, k] := SYSTEM.L2I(RU32());
      b := SYSTEM.L2I(RU32());
      IF b >= 0 THEN tbase[gid, k] := b END; (* 0xFFFFFFFF -> -1 *)
      n := SYSTEM.L2I(RU32()); (* nfields *)
      FOR i := 0 TO n-1 DO RStr(tname); RU32(); RU32() END
    ELSIF j = TK_POINTER THEN
      tto[gid, k] := SYSTEM.L2I(RU32())
    ELSIF j = TK_PROC THEN
      (* procedural type: skip payload (nparams, per-param type+var flag, result type) *)
      n := SYSTEM.L2I(RU32());
      FOR i := 0 TO n-1 DO RU32(); RU8() END;
      RU32()
    END
  END;
  (* runtime tags for records *)
  FOR k := 0 TO nt-1 DO
    IF tkind[gid, k] = TK_RECORD THEN
      INC(tagCounter);
      IF tagCounter >= 1024 THEN msgbuf := "too many record types"; Fatal END;
      rtTag[gid, k] := tagCounter; vmTagBase[tagCounter] := 0
    END
  END;
  FOR k := 0 TO nt-1 DO
    (* NB: & is NOT short-circuiting in Oberon -> nested IFs to guard indexes *)
    IF tkind[gid, k] = TK_RECORD THEN
      IF tbase[gid, k] >= 0 THEN
        vmTagBase[rtTag[gid, k]] := rtTag[gid, tbase[gid, k]]
      END
    END;
    IF tkind[gid, k] = TK_POINTER THEN
      IF tto[gid, k] >= 0 THEN
        IF tkind[gid, tto[gid, k]] = TK_RECORD THEN
          rtPtrTag[gid, k] := rtTag[gid, tto[gid, k]];
          rtPtrSize[gid, k] := tpayload[gid, tto[gid, k]]
        END
      END
    END
  END;
  (* allocate array globals *)
  FOR i := 0 TO gNg-1 DO
    IF tkind[gid, gTidx[i]] = TK_ARRAY THEN globals[gbase[gid] + gOff[i]] := AllocArray(gid, gTidx[i]) END
  END;
  (* procs *)
  np := SYSTEM.L2I(RU32());
  IF np > MAXPROC THEN msgbuf := "too many procs"; Fatal END;
  FOR k := 0 TO np-1 DO
    RStr(tname); RU8(); RU8(); (* name, exported, isBody *)
    npar := SYSTEM.L2I(RU32());
    FOR i := 0 TO npar-1 DO RStr(tname); RU32(); RU8() END;
    nloc := SYSTEM.L2I(RU32());
    phasResult[gid, k] := RU8(); RU32(); (* result type *)
    clen := SYSTEM.L2I(RU32());
    pnparams[gid, k] := npar; pnlocals[gid, k] := nloc;
    IF codeUsed + clen > CODESIZE THEN msgbuf := "code overflow"; Fatal END;
    pcofs[gid, k] := codeUsed; pclen[gid, k] := clen;
    (* translate bytecode to threaded code: opcode slot -> handler proc value, operands verbatim *)
    i := 0;
    WHILE i < clen DO
      op := SYSTEM.L2I(RU8()); INC(i);
      IF (op < 0) OR (op >= OP_COUNT) THEN msgbuf := "bad opcode"; Fatal END;
      code[codeUsed] := PROCC(handlers[op]); INC(codeUsed);
      IF op = OP_JUMPTABLE THEN
        n := SYSTEM.L2I(RU32()); i := i + 4;
        (* keep n verbatim as 4 byte-cells (threaded layout = 1 byte per cell) *)
        code[codeUsed] := n MOD 256; INC(codeUsed);
        code[codeUsed] := (n DIV 256) MOD 256; INC(codeUsed);
        code[codeUsed] := (n DIV 65536) MOD 256; INC(codeUsed);
        code[codeUsed] := (n DIV 16777216) MOD 256; INC(codeUsed);
        FOR j := 0 TO (n+2)*4-1 DO code[codeUsed] := RU8(); INC(codeUsed); INC(i) END
      ELSE
        FOR j := 0 TO OpLen(op)-1 DO code[codeUsed] := RU8(); INC(codeUsed); INC(i) END
      END
    END

  END;
  (* string pool *)
  ns := SYSTEM.L2I(RU32());
  IF ns > MAXSTR THEN msgbuf := "too many strings"; Fatal END;
  FOR k := 0 TO ns-1 DO RStr(tname); strRefs[gid, k] := AllocString(tname) END;
  (* now load the imports (recursion reuses fbuf, safe: this module is fully parsed) *)
  FOR i := 0 TO impCount-1 DO
    j := 0; WHILE impNames[i, j] # 0X DO tname[j] := impNames[i, j]; INC(j) END;
    tname[j] := 0X;
    map[gid, i+1] := LoadMod(tname, d)
  END;
  RETURN gid
END;

(* ---------- builtin tables (mirror bootstrap/src/rt.c) ---------- *)
PROCEDURE BuiltinNparams(id: INTEGER): INTEGER;
BEGIN
  CASE id OF
    0, 1, 10: RETURN 2
  | 2, 3, 5, 6, 7, 8, 9, 11, 12, 20, 21, 22, 23, 27, 28, 29, 31, 32: RETURN 1
  | 24, 30: RETURN 2
  | 25, 26: RETURN 3
  | 40, 41, 42, 44, 45, 46, 48: RETURN 2
  | 43, 50, 51, 52, 53, 54: RETURN 1
  ELSE RETURN 0 (* 4, 47, 49 *)
  END
END;

PROCEDURE BuiltinHasResult(id: INTEGER): INTEGER;
BEGIN
  CASE id OF
    20, 21, 23, 25, 27, 28, 29, 31, 32,
    40, 41, 42, 43, 44, 45, 46, 47, 49, 51, 52, 53, 54: RETURN 1
  ELSE RETURN 0
  END
END;

(* ---------- guest builtins (module 255), implemented via the host's Out/In/Files/SYSTEM ---------- *)
PROCEDURE CallBuiltin(id, base, nparams: INTEGER);
VAR ref, ndim, total, hdr, i, n, len, h, c, e: INTEGER;
    hf: Files.File; hx: INTEGER; hr: REAL; hc: CHAR;
    hb: ARRAY 256 OF CHAR; nm: ARRAY 256 OF CHAR;
BEGIN
  CASE id OF
    0: Out.Int(SYSTEM.L2I(stack[base]), SYSTEM.L2I(stack[base+1]))          (* Out.Int *)
  | 1: Out.Real(SYSTEM.BITSREAL(stack[base]), SYSTEM.L2I(stack[base+1]))     (* Out.Real *)
  | 2: Out.Char(CHR(SYSTEM.L2I(stack[base])))                                 (* Out.Char *)
  | 3: ref := SYSTEM.L2I(stack[base]);                                         (* Out.String *)
     IF ref # 0 THEN
       ndim := -SYSTEM.L2I(heap[ref]); total := SYSTEM.L2I(heap[ref+ndim+1]);
       i := 0;
       WHILE i < total DO
         IF heap[ref+ndim+2+i] = 0 THEN i := total
         ELSE Out.Char(CHR(SYSTEM.L2I(heap[ref+ndim+2+i]))); INC(i) END
       END
     END
  | 4: Out.Ln                                                                  (* Out.Ln *)
  | 5: In.Int(hx); MemWrite(stack[base], hx)                                   (* In.Int *)
  | 6: In.Real(hr); MemWrite(stack[base], SYSTEM.REALBITS(hr))                 (* In.Real *)
  | 7: In.Char(hc); MemWrite(stack[base], ORD(hc))                             (* In.Char *)
  | 8: In.Line(hb);                                                            (* In.Line *)
     ref := SYSTEM.L2I(MemRead(stack[base]));
     ndim := -SYSTEM.L2I(heap[ref]); total := SYSTEM.L2I(heap[ref+ndim+1]); hdr := ndim+2;
     n := 0; WHILE hb[n] # 0X DO INC(n) END;
     IF n > total - 1 THEN n := total - 1 END;
     FOR i := 0 TO n-1 DO heap[ref+hdr+i] := ORD(hb[i]) END;
     heap[ref+hdr+n] := 0
  | 9: haltCode := SYSTEM.L2I(stack[base]); running := FALSE                   (* HALT *)
  | 10: Out.Long(stack[base], SYSTEM.L2I(stack[base+1]))                       (* Out.Long *)
  | 11: Out.Byte(SYSTEM.L2I(stack[base]))                                      (* Out.Byte *)
  | 12: In.Byte(hx); MemWrite(stack[base], hx)                                  (* In.Byte, -1 at EOF *)
  | 20: RefToStr(stack[base], nm); hf := Files.Open(nm);                       (* Files.Open *)
      IF hf = NIL THEN stack[base] := 0 ELSE stack[base] := FileAlloc(hf) END
  | 21: RefToStr(stack[base], nm); hf := Files.Create(nm);                     (* Files.Create *)
      IF hf = NIL THEN stack[base] := 0 ELSE stack[base] := FileAlloc(hf) END
  | 22: h := FileHandle(stack[base]);                                           (* Files.Close *)
      IF h # 0 THEN Files.Close(fileTab[h-1]); fileTab[h-1] := NIL END
  | 23: h := FileHandle(stack[base]); ref := SYSTEM.L2I(stack[base]);          (* Files.ReadByte *)
      IF h = 0 THEN c := -1 ELSE c := Files.ReadByte(fileTab[h-1]) END;
      IF c < 0 THEN heap[ref+3] := 1 END;
      stack[base] := c
  | 24: h := FileHandle(stack[base]);                                           (* Files.WriteByte *)
      IF h # 0 THEN Files.WriteByte(fileTab[h-1], SYSTEM.L2I(stack[base+1])) END
  | 25: h := FileHandle(stack[base]); ref := SYSTEM.L2I(stack[base+1]);        (* Files.Read *)
      len := SYSTEM.L2I(stack[base+2]); n := 0;
      IF (h # 0) & (ref # 0) THEN
        ndim := -SYSTEM.L2I(heap[ref]); total := SYSTEM.L2I(heap[ref+ndim+1]); hdr := ndim+2;
        IF len > total THEN len := total END;
        i := 0;
        WHILE i < len DO
          c := Files.ReadByte(fileTab[h-1]);
          IF c < 0 THEN heap[ref+3] := 1; i := len ELSE heap[ref+hdr+i] := c; INC(i); INC(n) END
        END
      END;
      stack[base] := n
  | 26: h := FileHandle(stack[base]); ref := SYSTEM.L2I(stack[base+1]);        (* Files.Write *)
      len := SYSTEM.L2I(stack[base+2]);
      IF (h # 0) & (ref # 0) THEN
        ndim := -SYSTEM.L2I(heap[ref]); total := SYSTEM.L2I(heap[ref+ndim+1]); hdr := ndim+2;
        IF len > total THEN len := total END;
        FOR i := 0 TO len-1 DO
          Files.WriteByte(fileTab[h-1], SYSTEM.L2I(SYSTEM.BAND(heap[ref+hdr+i], 255)))
        END
      END
  | 27: h := FileHandle(stack[base]);                                           (* Files.Eof *)
      IF h = 0 THEN stack[base] := 1
      ELSE
        IF (heap[SYSTEM.L2I(stack[base])+3] # 0) OR Files.Eof(fileTab[h-1])
        THEN stack[base] := 1 ELSE stack[base] := 0 END
      END
  | 28: h := FileHandle(stack[base]);                                           (* Files.Length *)
      IF h = 0 THEN stack[base] := 0 ELSE stack[base] := Files.Length(fileTab[h-1]) END
  | 29: h := FileHandle(stack[base]);                                           (* Files.Pos *)
      IF h = 0 THEN stack[base] := 0 ELSE stack[base] := Files.Pos(fileTab[h-1]) END
  | 30: h := FileHandle(stack[base]);                                           (* Files.Set *)
      IF h # 0 THEN Files.Set(fileTab[h-1], stack[base+1]) END
  | 31: RefToStr(stack[base], nm);                                              (* Files.Delete *)
      IF Files.Delete(nm) THEN stack[base] := 1 ELSE stack[base] := 0 END
  | 32: RefToStr(stack[base], nm);                                              (* Files.Exists *)
      IF Files.Exists(nm) THEN stack[base] := 1 ELSE stack[base] := 0 END
  | 40: stack[base] := SYSTEM.BAND(stack[base], stack[base+1])                 (* SYSTEM.BAND *)
  | 41: stack[base] := SYSTEM.BOR(stack[base], stack[base+1])                  (* SYSTEM.BOR *)
  | 42: stack[base] := SYSTEM.BXOR(stack[base], stack[base+1])                 (* SYSTEM.BXOR *)
  | 43: stack[base] := SYSTEM.BNOT(stack[base])                                 (* SYSTEM.BNOT *)
  | 44: stack[base] := SYSTEM.LSH(stack[base], stack[base+1])                  (* SYSTEM.LSH *)
  | 45: stack[base] := SYSTEM.ROT(stack[base], stack[base+1])                  (* SYSTEM.ROT *)
  | 46: IF SYSTEM.BIT(stack[base], stack[base+1])                               (* SYSTEM.BIT *)
      THEN stack[base] := 1 ELSE stack[base] := 0 END
  | 47: stack[base] := hostArgc - 1                                             (* SYSTEM.ARGC *)
  | 48: i := SYSTEM.L2I(stack[base]);                                           (* SYSTEM.ARGV *)
      IF (i >= 0) & (i < hostArgc - 1) THEN SYSTEM.ARGV(i+1, hb) ELSE hb[0] := 0X END;
      ref := SYSTEM.L2I(MemRead(stack[base+1]));
      ndim := -SYSTEM.L2I(heap[ref]); total := SYSTEM.L2I(heap[ref+ndim+1]); hdr := ndim+2;
      n := 0; WHILE hb[n] # 0X DO INC(n) END;
      IF n > total - 1 THEN n := total - 1 END;
      FOR i := 0 TO n-1 DO heap[ref+hdr+i] := ORD(hb[i]) END;
      heap[ref+hdr+n] := 0
  | 49: stack[base] := SYSTEM.TICKS()                                          (* SYSTEM.TICKS *)
  | 50: haltCode := SYSTEM.L2I(stack[base]); running := FALSE                  (* SYSTEM.EXIT *)
  | 51: stack[base] := SYSTEM.L2I(stack[base])                                  (* SYSTEM.L2I *)
  | 52: stack[base] := SYSTEM.REALBITS(SYSTEM.BITSREAL(stack[base]))            (* SYSTEM.REALBITS *)
  | 53: stack[base] := SYSTEM.REALBITS(SYSTEM.BITSREAL(stack[base]))            (* SYSTEM.BITSREAL *)
  | 54: stack[base] := SYSTEM.REALBITS(SYSTEM.I2REAL(SYSTEM.L2I(stack[base])))  (* SYSTEM.I2REAL *)
  ELSE msgbuf := "unknown builtin"; Fatal
  END
END;

(* ---------- code pool readers ---------- *)
PROCEDURE RD32(o: INTEGER): LONGINT;
BEGIN RETURN code[o] + code[o+1]*256 + code[o+2]*65536 + code[o+3]*16777216 END;

PROCEDURE RD64(o: INTEGER): LONGINT;
VAR v: LONGINT;
BEGIN
  v := code[o] + code[o+1]*256 + code[o+2]*65536 + code[o+3]*16777216;
  v := v + code[o+4]*4294967296 + code[o+5]*1099511627776 + code[o+6]*281474976710656 + code[o+7]*72057594037927936;
  RETURN v
END;

(* ---------- the interpreter ---------- *)


(* ---------- threaded-code handlers (generated from the former CASE branches) ---------- *)
PROCEDURE H_OP_LOAD_LOCAL();
BEGIN
 u := RD32(cofs+pc); pc := pc+4;
        ld := SYSTEM.L2I(SYSTEM.LSH(u, -16)); off := SYSTEM.L2I(SYSTEM.BAND(u, 65535));
        fi := fp-1; WHILE ld > 0 DO fi := fslink[fi]; DEC(ld) END;
        IF fi < 0 THEN msgbuf := "bad static link"; Fatal END;
        slot := fbase[fi] + off; Push(stack[slot])
END H_OP_LOAD_LOCAL;

PROCEDURE H_OP_CONST_I();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; Push(ToI32(u))
END H_OP_CONST_I;

PROCEDURE H_OP_IADD();
BEGIN
 b := Pop(); a := Pop(); Push(ToI32(a + b))
END H_OP_IADD;

PROCEDURE H_OP_JZ();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; IF Pop() = 0 THEN pc := SYSTEM.L2I(u) END
END H_OP_JZ;

PROCEDURE H_OP_CALL();
BEGIN

        lmod := SYSTEM.L2I(code[cofs+pc]); pidx := SYSTEM.L2I(RD32(cofs+pc+4)); steps := SYSTEM.L2I(RD32(cofs+pc+8));
        pc := pc+12;
        IF lmod = 255 THEN
          n := BuiltinNparams(pidx); base := sp - n;
          CallBuiltin(pidx, base, n);
          sp := base + BuiltinHasResult(pidx)
        ELSE
          g := map[cur, lmod];
          base := sp - pnparams[g, pidx];
          fi := fp-1; st := steps;
          WHILE (st > 0) & (fi >= 0) DO fi := fslink[fi]; DEC(st) END;
          IF fp >= FRAMES THEN msgbuf := "frame overflow"; Fatal END;
          fpc[fp-1] := pc;
          fmod[fp] := g; fproc[fp] := pidx; fpc[fp] := 0; fbase[fp] := base; fslink[fp] := fi;
          fextra[fp] := 0; fcref[fp] := 0; INC(fp);
          sp := base + pnlocals[g, pidx];
          pc := 0
        END
END H_OP_CALL;

PROCEDURE H_OP_STORE_LOCAL();
BEGIN
 u := RD32(cofs+pc); pc := pc+4;
        ld := SYSTEM.L2I(SYSTEM.LSH(u, -16)); off := SYSTEM.L2I(SYSTEM.BAND(u, 65535));
        fi := fp-1; WHILE ld > 0 DO fi := fslink[fi]; DEC(ld) END;
        slot := fbase[fi] + off; stack[slot] := Pop()
END H_OP_STORE_LOCAL;

PROCEDURE H_OP_INE();
BEGIN
 b := Pop(); a := Pop(); IF a # b THEN Push(1) ELSE Push(0) END
END H_OP_INE;

PROCEDURE H_OP_ADDR_LOCAL();
BEGIN
 u := RD32(cofs+pc); pc := pc+4;
        ld := SYSTEM.L2I(SYSTEM.LSH(u, -16)); off := SYSTEM.L2I(SYSTEM.BAND(u, 65535));
        fi := fp-1; WHILE ld > 0 DO fi := fslink[fi]; DEC(ld) END;
        slot := fbase[fi] + off; Push(slot)
END H_OP_ADDR_LOCAL;

PROCEDURE H_OP_ILT();
BEGIN
 b := Pop(); a := Pop(); IF a < b THEN Push(1) ELSE Push(0) END
END H_OP_ILT;

PROCEDURE H_OP_JMP();
BEGIN
 pc := SYSTEM.L2I(RD32(cofs+pc))
END H_OP_JMP;

PROCEDURE H_OP_ELEM_ADDR();
BEGIN
 b := Pop(); a := Pop();
        IF a = 0 THEN msgbuf := "nil pointer dereference"; Fatal END;
        tg := heap[SYSTEM.L2I(a)];
        IF tg >= 0 THEN msgbuf := "indexing non-array"; Fatal END;
        n := SYSTEM.L2I(-tg); t := heap[SYSTEM.L2I(a) + n + 1];
        IF (b < 0) OR (b >= t) THEN msgbuf := "index out of range"; Fatal END;
        Push(SYSTEM.LSH(2, 56) + a + n + 2 + b)
END H_OP_ELEM_ADDR;

PROCEDURE H_OP_IEQ();
BEGIN
 b := Pop(); a := Pop(); IF a = b THEN Push(1) ELSE Push(0) END
END H_OP_IEQ;

PROCEDURE H_OP_AADD();
BEGIN
 b := Pop(); a := Pop(); Push(a + b)
END H_OP_AADD;

PROCEDURE H_OP_LOAD_AT();
BEGIN
 a := Pop(); Push(MemRead(a))
END H_OP_LOAD_AT;

PROCEDURE H_OP_STORE_AT();
BEGIN
 b := Pop(); a := Pop(); MemWrite(a, b)
END H_OP_STORE_AT;

PROCEDURE H_OP_LOAD_GLOBAL();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod]; Push(globals[gbase[g] + SYSTEM.L2I(u)])
END H_OP_LOAD_GLOBAL;

PROCEDURE H_OP_ISUB();
BEGIN
 b := Pop(); a := Pop(); Push(ToI32(a - b))
END H_OP_ISUB;

PROCEDURE H_OP_IMUL();
BEGIN
 b := Pop(); a := Pop(); Push(ToI32(a * b))
END H_OP_IMUL;

PROCEDURE H_OP_STORE_GLOBAL();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod]; globals[gbase[g] + SYSTEM.L2I(u)] := Pop()
END H_OP_STORE_GLOBAL;

PROCEDURE H_OP_ADDR_GLOBAL();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        Push(SYSTEM.LSH(1, 56) + SYSTEM.LSH(map[cur, lmod], 48) + u)
END H_OP_ADDR_GLOBAL;

PROCEDURE H_OP_CONST_R();
BEGIN
 u := RD64(cofs+pc); pc := pc+8; Push(u)
END H_OP_CONST_R;

PROCEDURE H_OP_CONST_S();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; Push(strRefs[cur, SYSTEM.L2I(u)])
END H_OP_CONST_S;

PROCEDURE H_OP_CONST_L();
BEGIN
 u := RD64(cofs+pc); pc := pc+8; Push(u)
END H_OP_CONST_L;

PROCEDURE H_OP_TO_ADDR();
BEGIN
 a := Pop(); Push(SYSTEM.LSH(2, 56) + a)
END H_OP_TO_ADDR;

PROCEDURE H_OP_RET();
BEGIN
 hres := phasResult[fmod[fp-1], fproc[fp-1]];
        IF hres = 1 THEN rv := Pop() ELSE rv := 0 END;
        sp := fbase[fp-1]; e := fextra[fp-1]; cr := fcref[fp-1];
        IF cr # 0 THEN  (* closure: write captured frames back into the closure object *)
          n := SYSTEM.L2I(heap[cr+3]); off := 4; jb := fp-1-e;
          FOR i := 0 TO n-1 DO
            cf := jb + (n-1-i); nl := SYSTEM.L2I(heap[cr+off]);
            FOR k := 0 TO nl-1 DO heap[cr+off+1+k] := stack[fbase[cf]+k] END;
            off := off + 1 + nl
          END
        END;
        fp := fp - 1 - e;
        IF fp = 0 THEN running := FALSE
        ELSE IF hres = 1 THEN Push(rv) END
        END
END H_OP_RET;

PROCEDURE H_OP_NEW();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod];
        IF tkind[g, SYSTEM.L2I(u)] # TK_POINTER THEN msgbuf := "NEW on non-pointer type"; Fatal END;
        to := tto[g, SYSTEM.L2I(u)];
        IF to < 0 THEN msgbuf := "NEW on non-pointer type"; Fatal END;
        IF tkind[g, to] = TK_RECORD THEN
          tag := rtPtrTag[g, SYSTEM.L2I(u)]; n := rtPtrSize[g, SYSTEM.L2I(u)];
          IF tag = 0 THEN msgbuf := "NEW on non-record pointer"; Fatal END;
          slot := HeapAlloc(2 + n); heap[slot] := tag; heap[slot+1] := n; Push(slot)
        ELSIF tkind[g, to] = TK_ARRAY THEN
          IF ttotal[g, to] = 1073741823 THEN msgbuf := "NEW on open array pointer"; Fatal END;
          Push(AllocArray(g, to))
        ELSE msgbuf := "NEW on unsupported pointee"; Fatal END
END H_OP_NEW;

PROCEDURE H_OP_DISPOSE();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod]; a := Pop(); ref := SYSTEM.L2I(MemRead(a));
        IF ref # 0 THEN
          IF (tkind[g, SYSTEM.L2I(u)] = TK_POINTER) & (tto[g, SYSTEM.L2I(u)] >= 0) THEN
            n := ObjSize(g, tto[g, SYSTEM.L2I(u)]);
            IF n <= 0 THEN msgbuf := "DISPOSE on unsupported pointee"; Fatal END;
            HeapFree(ref, n); MemWrite(a, 0)
          ELSE msgbuf := "DISPOSE on non-pointer type"; Fatal END
        END
END H_OP_DISPOSE;

PROCEDURE H_OP_PROCVAL();
BEGIN
 lmod := SYSTEM.L2I(RD32(cofs+pc)); pidx := SYSTEM.L2I(RD32(cofs+pc+4));
        steps := SYSTEM.L2I(RD32(cofs+pc+8)); pc := pc+12;
        g := map[cur, lmod];
        IF steps < 0 THEN  (* 0xFFFFFFFF sentinel: module-level proc -> plain value *)
          Push(TAG_PROC * SHIFT56 + g * SHIFT48 + pidx)
        ELSE  (* closure: snapshot the static-link chain from the defining frame down to root *)
          fi := fp-1; st := steps;
          WHILE st > 0 DO fi := fslink[fi]; DEC(st) END;
          IF fi < 0 THEN msgbuf := "bad static link (closure)"; Fatal END;
          n := 0; jb := fi; WHILE jb >= 0 DO INC(n); jb := fslink[jb] END;
          total := 4; jb := fi;
          WHILE jb >= 0 DO total := total + 1 + pnlocals[fmod[jb], fproc[jb]]; jb := fslink[jb] END;
          ref := HeapAlloc(total);
          heap[ref] := CLOSURE_TAG; heap[ref+1] := g; heap[ref+2] := pidx; heap[ref+3] := n;
          off := 4; jb := fi;
          WHILE jb >= 0 DO
            nl := pnlocals[fmod[jb], fproc[jb]];
            heap[ref+off] := nl; INC(off);
            FOR k := 0 TO nl-1 DO heap[ref+off] := stack[fbase[jb]+k]; INC(off) END;
            jb := fslink[jb]
          END;
          Push(ref)
        END
END H_OP_PROCVAL;

PROCEDURE H_OP_CALLP();
BEGIN

        u := Pop();
        IF u = 0 THEN msgbuf := "call of NIL procedure"; Fatal END;
        IF SYSTEM.L2I(SYSTEM.LSH(u, -56)) = TAG_PROC THEN
          g := SYSTEM.L2I(SYSTEM.BAND(SYSTEM.LSH(u, -48), 255));
          pidx := SYSTEM.L2I(SYSTEM.BAND(u, MASK32));
          fpc[fp-1] := pc;
          base := sp - pnparams[g, pidx];
          fi := fp-1;
          IF fp >= FRAMES THEN msgbuf := "frame overflow"; Fatal END;
          fmod[fp] := g; fproc[fp] := pidx; fpc[fp] := 0; fbase[fp] := base; fslink[fp] := fi;
          fextra[fp] := 0; fcref[fp] := 0; INC(fp);
          sp := base + pnlocals[g, pidx];
          pc := 0
        ELSE  (* closure: materialize captured frames, then push the callee frame *)
          ref := SYSTEM.L2I(SYSTEM.BAND(u, MASK56));
          IF (ref <= 0) OR (heap[ref] # CLOSURE_TAG) THEN msgbuf := "call of non-procedure value"; Fatal END;
          g := SYSTEM.L2I(heap[ref+1]); pidx := SYSTEM.L2I(heap[ref+2]); n := SYSTEM.L2I(heap[ref+3]);
          fpc[fp-1] := pc;
          base := sp - pnparams[g, pidx];
          capBase := base + pnlocals[g, pidx];
          off := 4; total := 0;
          FOR i := 0 TO n-1 DO scratch[i] := off; nl := SYSTEM.L2I(heap[ref+off]); off := off + 1 + nl; total := total + nl END;
          IF capBase + total >= STACKSIZE THEN msgbuf := "stack overflow"; Fatal END;
          bi := capBase;
          i := n-1;
          WHILE i >= 0 DO
            nl := SYSTEM.L2I(heap[ref+scratch[i]]);
            FOR k := 0 TO nl-1 DO stack[bi+k] := heap[ref+scratch[i]+1+k] END;
            bi := bi + nl; DEC(i)
          END;
          prev := -1;
          i := n-1;
          WHILE i >= 0 DO
            IF fp >= FRAMES THEN msgbuf := "frame overflow"; Fatal END;
            bas := capBase;
            FOR j := i+1 TO n-1 DO bas := bas + SYSTEM.L2I(heap[ref+scratch[j]]) END;
            fmod[fp] := 0; fproc[fp] := 0; fpc[fp] := 0; fbase[fp] := bas; fslink[fp] := prev;
            fextra[fp] := 0; fcref[fp] := 0;
            prev := fp; INC(fp); DEC(i)
          END;
          IF fp >= FRAMES THEN msgbuf := "frame overflow"; Fatal END;
          fmod[fp] := g; fproc[fp] := pidx; fpc[fp] := 0; fbase[fp] := base; fslink[fp] := prev;
          fextra[fp] := n; fcref[fp] := ref; INC(fp);
          sp := capBase + total;
          pc := 0
        END
END H_OP_CALLP;

PROCEDURE H_OP_ALLOC_ARRAY();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod]; Push(AllocArray(g, SYSTEM.L2I(u)))
END H_OP_ALLOC_ARRAY;

PROCEDURE H_OP_LEN();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; a := Pop();
        IF a = 0 THEN msgbuf := "LEN of nil"; Fatal END;
        tg := heap[SYSTEM.L2I(a)];
        IF tg >= 0 THEN msgbuf := "LEN of non-array"; Fatal END;
        n := SYSTEM.L2I(-tg);
        IF (SYSTEM.L2I(u) < 0) OR (SYSTEM.L2I(u) >= n) THEN msgbuf := "bad LEN dimension"; Fatal END;
        Push(heap[SYSTEM.L2I(a) + 1 + SYSTEM.L2I(u)])
END H_OP_LEN;

PROCEDURE H_OP_ISTYPE_B();
BEGIN
 lmod := SYSTEM.L2I(code[cofs+pc]); u := RD32(cofs+pc+1); pc := pc+5;
        g := map[cur, lmod]; tag := rtTag[g, SYSTEM.L2I(u)];
        a := Pop(); ok := 0;
        IF a # 0 THEN
          t := heap[SYSTEM.L2I(a)];
          WHILE (t > 0) & (ok = 0) DO
            IF t = tag THEN ok := 1 ELSE t := vmTagBase[SYSTEM.L2I(t)] END
          END
        END;
        IF op = OP_CHECKTYPE THEN
          IF ok = 0 THEN msgbuf := "type guard failed"; Fatal END;
          Push(a)
        ELSE Push(ok)
        END
END H_OP_ISTYPE_B;
PROCEDURE H_OP_ISTYPE();
BEGIN op := OP_ISTYPE; H_OP_ISTYPE_B() END H_OP_ISTYPE;
PROCEDURE H_OP_CHECKTYPE();
BEGIN op := OP_CHECKTYPE; H_OP_ISTYPE_B() END H_OP_CHECKTYPE;

PROCEDURE H_OP_COPY();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; b := Pop(); a := Pop();
        FOR i := 0 TO SYSTEM.L2I(u)-1 DO MemWrite(a + i, MemRead(b + i)) END
END H_OP_COPY;

PROCEDURE H_OP_COPY_STR();
BEGIN
 a := Pop(); b := Pop(); (* a = dstRef, b = srcRef *)
        IF (b = 0) OR (a = 0) THEN msgbuf := "COPY with nil array"; Fatal END;
        i := SYSTEM.L2I(-heap[SYSTEM.L2I(b)]); n := SYSTEM.L2I(-heap[SYSTEM.L2I(a)]);
        ld := SYSTEM.L2I(heap[SYSTEM.L2I(b) + i + 1]); off := SYSTEM.L2I(heap[SYSTEM.L2I(a) + n + 1]);
        IF ld < off THEN off := ld END;
        FOR i := 0 TO off-1 DO heap[SYSTEM.L2I(a) + n + 2 + i] := heap[SYSTEM.L2I(b) + SYSTEM.L2I(-heap[SYSTEM.L2I(b)]) + 2 + i] END
END H_OP_COPY_STR;

PROCEDURE H_OP_DUP();
BEGIN
 Push(stack[sp-1])
END H_OP_DUP;

PROCEDURE H_OP_DROP();
BEGIN
 u := Pop()
END H_OP_DROP;

PROCEDURE H_OP_SWAP();
BEGIN
 b := Pop(); a := Pop(); Push(b); Push(a)
END H_OP_SWAP;

PROCEDURE H_OP_SHL();
BEGIN
 b := Pop(); a := Pop(); Push(ToI32(SYSTEM.LSH(SYSTEM.BAND(a, MASK32), SYSTEM.BAND(b, 31))))
END H_OP_SHL;

PROCEDURE H_OP_SHR();
BEGIN
 b := Pop(); a := Pop(); Push(ToI32(SYSTEM.LSH(SYSTEM.BAND(a, MASK32), -SYSTEM.BAND(b, 31))))
END H_OP_SHR;

PROCEDURE H_OP_IDIV();
BEGIN
 b := Pop(); a := Pop();
        IF b = 0 THEN msgbuf := "division by zero"; Fatal END; Push(a DIV b)
END H_OP_IDIV;

PROCEDURE H_OP_IMOD();
BEGIN
 b := Pop(); a := Pop();
        IF b = 0 THEN msgbuf := "division by zero"; Fatal END; Push(a MOD b)
END H_OP_IMOD;

PROCEDURE H_OP_ILE();
BEGIN
 b := Pop(); a := Pop(); IF a <= b THEN Push(1) ELSE Push(0) END
END H_OP_ILE;

PROCEDURE H_OP_IGT();
BEGIN
 b := Pop(); a := Pop(); IF a > b THEN Push(1) ELSE Push(0) END
END H_OP_IGT;

PROCEDURE H_OP_IGE();
BEGIN
 b := Pop(); a := Pop(); IF a >= b THEN Push(1) ELSE Push(0) END
END H_OP_IGE;

PROCEDURE H_OP_JNZ();
BEGIN
 u := RD32(cofs+pc); pc := pc+4; IF Pop() # 0 THEN pc := SYSTEM.L2I(u) END
END H_OP_JNZ;

PROCEDURE H_OP_INEG();
BEGIN
 a := Pop(); Push(ToI32(-a))
END H_OP_INEG;

PROCEDURE H_OP_IABS();
BEGIN
 a := Pop(); IF a < 0 THEN Push(ToI32(-a)) ELSE Push(a) END
END H_OP_IABS;

PROCEDURE H_OP_IODD();
BEGIN
 a := Pop(); Push(SYSTEM.BAND(a, 1))
END H_OP_IODD;

PROCEDURE H_OP_FADD();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.REALBITS(SYSTEM.BITSREAL(a) + SYSTEM.BITSREAL(b)))
END H_OP_FADD;

PROCEDURE H_OP_FSUB();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.REALBITS(SYSTEM.BITSREAL(a) - SYSTEM.BITSREAL(b)))
END H_OP_FSUB;

PROCEDURE H_OP_FMUL();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.REALBITS(SYSTEM.BITSREAL(a) * SYSTEM.BITSREAL(b)))
END H_OP_FMUL;

PROCEDURE H_OP_FDIV();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.REALBITS(SYSTEM.BITSREAL(a) / SYSTEM.BITSREAL(b)))
END H_OP_FDIV;

PROCEDURE H_OP_FNEG();
BEGIN
 a := Pop(); Push(SYSTEM.REALBITS(-SYSTEM.BITSREAL(a)))
END H_OP_FNEG;

PROCEDURE H_OP_FABS();
BEGIN
 a := Pop(); x := SYSTEM.BITSREAL(a); IF x < 0.0 THEN Push(SYSTEM.REALBITS(-x)) ELSE Push(a) END
END H_OP_FABS;

PROCEDURE H_OP_FFLOOR();
BEGIN
 a := Pop(); Push(FLOOR(SYSTEM.BITSREAL(a)))
END H_OP_FFLOOR;

PROCEDURE H_OP_I2F();
BEGIN
 a := Pop(); Push(SYSTEM.REALBITS(SYSTEM.I2REAL(SYSTEM.L2I(a))))
END H_OP_I2F;

PROCEDURE H_OP_F2I();
BEGIN
 a := Pop(); Push(ENTIER(SYSTEM.BITSREAL(a)))
END H_OP_F2I;

PROCEDURE H_OP_FLT();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x < y THEN Push(1) ELSE Push(0) END
END H_OP_FLT;

PROCEDURE H_OP_FLE();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x <= y THEN Push(1) ELSE Push(0) END
END H_OP_FLE;

PROCEDURE H_OP_FGT();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x > y THEN Push(1) ELSE Push(0) END
END H_OP_FGT;

PROCEDURE H_OP_FGE();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x >= y THEN Push(1) ELSE Push(0) END
END H_OP_FGE;

PROCEDURE H_OP_FEQ();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x = y THEN Push(1) ELSE Push(0) END
END H_OP_FEQ;

PROCEDURE H_OP_FNE();
BEGIN
 b := Pop(); a := Pop(); x := SYSTEM.BITSREAL(a); y := SYSTEM.BITSREAL(b); IF x # y THEN Push(1) ELSE Push(0) END
END H_OP_FNE;

PROCEDURE H_OP_EQ();
BEGIN
 b := Pop(); a := Pop(); IF a = b THEN Push(1) ELSE Push(0) END
END H_OP_EQ;

PROCEDURE H_OP_NE();
BEGIN
 b := Pop(); a := Pop(); IF a # b THEN Push(1) ELSE Push(0) END
END H_OP_NE;

PROCEDURE H_OP_AND();
BEGIN
 b := Pop(); a := Pop(); IF (a # 0) & (b # 0) THEN Push(1) ELSE Push(0) END
END H_OP_AND;

PROCEDURE H_OP_OR();
BEGIN
 b := Pop(); a := Pop(); IF (a # 0) OR (b # 0) THEN Push(1) ELSE Push(0) END
END H_OP_OR;

PROCEDURE H_OP_NOT();
BEGIN
 a := Pop(); IF a = 0 THEN Push(1) ELSE Push(0) END
END H_OP_NOT;

PROCEDURE H_OP_SET_UNION();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.BAND(SYSTEM.BOR(a, b), MASK32))
END H_OP_SET_UNION;

PROCEDURE H_OP_SET_DIFF();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.BAND(SYSTEM.BAND(a, SYSTEM.BNOT(b)), MASK32))
END H_OP_SET_DIFF;

PROCEDURE H_OP_SET_INTER();
BEGIN
 b := Pop(); a := Pop(); Push(SYSTEM.BAND(SYSTEM.BAND(a, b), MASK32))
END H_OP_SET_INTER;

PROCEDURE H_OP_SET_MEMBER();
BEGIN
 a := Pop(); b := Pop();
        IF (b < 0) OR (b > 31) THEN msgbuf := "set element out of range"; Fatal END;
        Push(SYSTEM.BAND(SYSTEM.LSH(a, -b), 1))
END H_OP_SET_MEMBER;

PROCEDURE H_OP_LADD();
BEGIN
 b := Pop(); a := Pop(); Push(a + b)
END H_OP_LADD;

PROCEDURE H_OP_LSUB();
BEGIN
 b := Pop(); a := Pop(); Push(a - b)
END H_OP_LSUB;

PROCEDURE H_OP_LMUL();
BEGIN
 b := Pop(); a := Pop(); Push(a * b)
END H_OP_LMUL;

PROCEDURE H_OP_LDIV();
BEGIN
 b := Pop(); a := Pop();
        IF b = 0 THEN msgbuf := "division by zero"; Fatal END; Push(a DIV b)
END H_OP_LDIV;

PROCEDURE H_OP_LMOD();
BEGIN
 b := Pop(); a := Pop();
        IF b = 0 THEN msgbuf := "division by zero"; Fatal END; Push(a MOD b)
END H_OP_LMOD;

PROCEDURE H_OP_LNEG();
BEGIN
 a := Pop(); Push(-a)
END H_OP_LNEG;

PROCEDURE H_OP_LABS();
BEGIN
 a := Pop(); IF a < 0 THEN Push(-a) ELSE Push(a) END
END H_OP_LABS;

PROCEDURE H_OP_LODD();
BEGIN
 a := Pop(); Push(SYSTEM.BAND(a, 1))
END H_OP_LODD;

PROCEDURE H_OP_LLT();
BEGIN
 b := Pop(); a := Pop(); IF a < b THEN Push(1) ELSE Push(0) END
END H_OP_LLT;

PROCEDURE H_OP_LLE();
BEGIN
 b := Pop(); a := Pop(); IF a <= b THEN Push(1) ELSE Push(0) END
END H_OP_LLE;

PROCEDURE H_OP_LGT();
BEGIN
 b := Pop(); a := Pop(); IF a > b THEN Push(1) ELSE Push(0) END
END H_OP_LGT;

PROCEDURE H_OP_LGE();
BEGIN
 b := Pop(); a := Pop(); IF a >= b THEN Push(1) ELSE Push(0) END
END H_OP_LGE;

PROCEDURE H_OP_LEQ();
BEGIN
 b := Pop(); a := Pop(); IF a = b THEN Push(1) ELSE Push(0) END
END H_OP_LEQ;

PROCEDURE H_OP_LNE();
BEGIN
 b := Pop(); a := Pop(); IF a # b THEN Push(1) ELSE Push(0) END
END H_OP_LNE;

PROCEDURE H_OP_L2I();
BEGIN
 a := Pop(); Push(ToI32(a))
END H_OP_L2I;

PROCEDURE H_OP_JUMPTABLE();
BEGIN
 u := RD32(cofs+pc); a := RD32(cofs+pc+4); b := RD32(cofs+pc+8); pc := pc+12;
        rv := Pop(); i := SYSTEM.L2I(rv - a);
        IF (i >= 0) & (i < SYSTEM.L2I(u)) THEN pc := SYSTEM.L2I(RD32(cofs + pc + 4*i))
        ELSE pc := SYSTEM.L2I(b) END
END H_OP_JUMPTABLE;

PROCEDURE H_OP_NOP();
BEGIN
 (* nothing *)
END H_OP_NOP;


PROCEDURE InitHandlers();
BEGIN
  handlers[OP_LOAD_LOCAL] := H_OP_LOAD_LOCAL;
  handlers[OP_CONST_I] := H_OP_CONST_I;
  handlers[OP_IADD] := H_OP_IADD;
  handlers[OP_JZ] := H_OP_JZ;
  handlers[OP_CALL] := H_OP_CALL;
  handlers[OP_STORE_LOCAL] := H_OP_STORE_LOCAL;
  handlers[OP_INE] := H_OP_INE;
  handlers[OP_ADDR_LOCAL] := H_OP_ADDR_LOCAL;
  handlers[OP_ILT] := H_OP_ILT;
  handlers[OP_JMP] := H_OP_JMP;
  handlers[OP_ELEM_ADDR] := H_OP_ELEM_ADDR;
  handlers[OP_IEQ] := H_OP_IEQ;
  handlers[OP_AADD] := H_OP_AADD;
  handlers[OP_LOAD_AT] := H_OP_LOAD_AT;
  handlers[OP_STORE_AT] := H_OP_STORE_AT;
  handlers[OP_LOAD_GLOBAL] := H_OP_LOAD_GLOBAL;
  handlers[OP_ISUB] := H_OP_ISUB;
  handlers[OP_IMUL] := H_OP_IMUL;
  handlers[OP_STORE_GLOBAL] := H_OP_STORE_GLOBAL;
  handlers[OP_ADDR_GLOBAL] := H_OP_ADDR_GLOBAL;
  handlers[OP_CONST_R] := H_OP_CONST_R;
  handlers[OP_CONST_S] := H_OP_CONST_S;
  handlers[OP_CONST_L] := H_OP_CONST_L;
  handlers[OP_TO_ADDR] := H_OP_TO_ADDR;
  handlers[OP_RET] := H_OP_RET;
  handlers[OP_NEW] := H_OP_NEW;
  handlers[OP_DISPOSE] := H_OP_DISPOSE;
  handlers[OP_PROCVAL] := H_OP_PROCVAL;
  handlers[OP_CALLP] := H_OP_CALLP;
  handlers[OP_ALLOC_ARRAY] := H_OP_ALLOC_ARRAY;
  handlers[OP_LEN] := H_OP_LEN;
  handlers[OP_ISTYPE] := H_OP_ISTYPE;
  handlers[OP_CHECKTYPE] := H_OP_CHECKTYPE;
  handlers[OP_COPY] := H_OP_COPY;
  handlers[OP_COPY_STR] := H_OP_COPY_STR;
  handlers[OP_DUP] := H_OP_DUP;
  handlers[OP_DROP] := H_OP_DROP;
  handlers[OP_SWAP] := H_OP_SWAP;
  handlers[OP_SHL] := H_OP_SHL;
  handlers[OP_SHR] := H_OP_SHR;
  handlers[OP_IDIV] := H_OP_IDIV;
  handlers[OP_IMOD] := H_OP_IMOD;
  handlers[OP_ILE] := H_OP_ILE;
  handlers[OP_IGT] := H_OP_IGT;
  handlers[OP_IGE] := H_OP_IGE;
  handlers[OP_JNZ] := H_OP_JNZ;
  handlers[OP_INEG] := H_OP_INEG;
  handlers[OP_IABS] := H_OP_IABS;
  handlers[OP_IODD] := H_OP_IODD;
  handlers[OP_FADD] := H_OP_FADD;
  handlers[OP_FSUB] := H_OP_FSUB;
  handlers[OP_FMUL] := H_OP_FMUL;
  handlers[OP_FDIV] := H_OP_FDIV;
  handlers[OP_FNEG] := H_OP_FNEG;
  handlers[OP_FABS] := H_OP_FABS;
  handlers[OP_FFLOOR] := H_OP_FFLOOR;
  handlers[OP_I2F] := H_OP_I2F;
  handlers[OP_F2I] := H_OP_F2I;
  handlers[OP_FLT] := H_OP_FLT;
  handlers[OP_FLE] := H_OP_FLE;
  handlers[OP_FGT] := H_OP_FGT;
  handlers[OP_FGE] := H_OP_FGE;
  handlers[OP_FEQ] := H_OP_FEQ;
  handlers[OP_FNE] := H_OP_FNE;
  handlers[OP_EQ] := H_OP_EQ;
  handlers[OP_NE] := H_OP_NE;
  handlers[OP_AND] := H_OP_AND;
  handlers[OP_OR] := H_OP_OR;
  handlers[OP_NOT] := H_OP_NOT;
  handlers[OP_SET_UNION] := H_OP_SET_UNION;
  handlers[OP_SET_DIFF] := H_OP_SET_DIFF;
  handlers[OP_SET_INTER] := H_OP_SET_INTER;
  handlers[OP_SET_MEMBER] := H_OP_SET_MEMBER;
  handlers[OP_LADD] := H_OP_LADD;
  handlers[OP_LSUB] := H_OP_LSUB;
  handlers[OP_LMUL] := H_OP_LMUL;
  handlers[OP_LDIV] := H_OP_LDIV;
  handlers[OP_LMOD] := H_OP_LMOD;
  handlers[OP_LNEG] := H_OP_LNEG;
  handlers[OP_LABS] := H_OP_LABS;
  handlers[OP_LODD] := H_OP_LODD;
  handlers[OP_LLT] := H_OP_LLT;
  handlers[OP_LLE] := H_OP_LLE;
  handlers[OP_LGT] := H_OP_LGT;
  handlers[OP_LGE] := H_OP_LGE;
  handlers[OP_LEQ] := H_OP_LEQ;
  handlers[OP_LNE] := H_OP_LNE;
  handlers[OP_L2I] := H_OP_L2I;
  handlers[OP_JUMPTABLE] := H_OP_JUMPTABLE;
  handlers[OP_NOP] := H_OP_NOP;
END InitHandlers;

(* ---------- the interpreter: threaded-code dispatch ----------
   Each guest instruction slot holds a handler procedure value (TAG_PROC cell);
   the loop fetches it and calls it indirectly: no opcode decode, no linear CASE. *)
PROCEDURE Run();
VAR h: Handler; oldfp: INTEGER;
BEGIN
  fmod[0] := 0; fproc[0] := 0; fpc[0] := 0; fbase[0] := 0; fslink[0] := -1;
  fextra[0] := 0; fcref[0] := 0;
  fp := 1; sp := pnlocals[0, 0]; running := TRUE;
  WHILE running & (fp > 0) DO
    cur := fmod[fp-1]; cofs := pcofs[cur, fproc[fp-1]]; pc := fpc[fp-1]; oldfp := fp;
    h := PROCV(code[cofs + pc]); INC(pc);
    h();
    IF fp = oldfp THEN fpc[fp-1] := pc END
  END
END;


(* ---------- main ---------- *)


PROCEDURE Main();
VAR i, j, lastSep: INTEGER;
BEGIN
  hostArgc := SYSTEM.ARGC;
  IF hostArgc < 1 THEN Out.String("usage: vm <file.obc> [args...]"); Out.Ln; SYSTEM.EXIT(2) END;
  SYSTEM.ARGV(0, path);
  (* split dir / basename-without-extension *)
  i := 0; lastSep := -1;
  WHILE path[i] # 0X DO
    IF (path[i] = CHR(47)) OR (path[i] = CHR(92)) THEN lastSep := i END; (* '/' or '\' *)
    INC(i)
  END;
  IF lastSep >= 0 THEN
    FOR j := 0 TO lastSep-1 DO dir[j] := path[j] END;
    dir[lastSep] := 0X
  ELSE
    dir[0] := CHR(46); dir[1] := 0X (* "." *)
  END;
  i := lastSep + 1; j := 0;
  WHILE (path[i] # 0X) & (path[i] # CHR(46)) DO name[j] := path[i]; INC(i); INC(j) END;
  name[j] := 0X;
  nmods := 0; heapUsed := 1; freeHead := 0; codeUsed := 0; globalsUsed := 0; tagCounter := 0;
  fp := 0; sp := 0; running := FALSE; haltCode := 0;
  InitHandlers();
  LoadMod(name, dir);

  Run();
  SYSTEM.EXIT(haltCode)
END;

BEGIN Main()
END VM.
