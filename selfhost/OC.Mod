MODULE OC;
(* OC.Mod — compilateur Oberon-07 en Oberon (auto-hébergement, étape 6).
   Port single-pass de bootstrap/src/parser.c : lexer = OCS.Mod, émission .obc
   identique au stage-0 (vérifié par cmp sur les exemples).
   usage: obvm OC.obc <file.Mod> [-o <file.obc>] *)
IMPORT Out, Files, SYSTEM, OCS;

CONST
  (* opcodes — MUST match bootstrap/src/ob.h (append-only) *)
  OP_NOP=0; OP_CONST_I=1; OP_CONST_R=2; OP_CONST_S=3;
  OP_LOAD_LOCAL=4; OP_STORE_LOCAL=5; OP_ADDR_LOCAL=6;
  OP_LOAD_GLOBAL=7; OP_STORE_GLOBAL=8; OP_ADDR_GLOBAL=9;
  OP_LOAD_AT=10; OP_STORE_AT=11; OP_TO_ADDR=12;
  OP_IADD=13; OP_ISUB=14; OP_IMUL=15; OP_IDIV=16; OP_IMOD=17; OP_INEG=18; OP_IABS=19; OP_IODD=20;
  OP_FADD=21; OP_FSUB=22; OP_FMUL=23; OP_FDIV=24; OP_FNEG=25; OP_FABS=26; OP_FFLOOR=27;
  OP_I2F=28; OP_F2I=29;
  OP_ILT=30; OP_ILE=31; OP_IGT=32; OP_IGE=33; OP_IEQ=34; OP_INE=35;
  OP_FLT=36; OP_FLE=37; OP_FGT=38; OP_FGE=39; OP_FEQ=40; OP_FNE=41;
  OP_EQ=42; OP_NE=43; OP_AND=44; OP_OR=45; OP_NOT=46;
  OP_SET_UNION=47; OP_SET_DIFF=48; OP_SET_INTER=49; OP_SET_MEMBER=50;
  OP_JMP=51; OP_JZ=52; OP_JNZ=53; OP_CALL=54; OP_RET=55;
  OP_NEW=56; OP_ALLOC_ARRAY=57; OP_LEN=58; OP_ISTYPE=59; OP_CHECKTYPE=60;
  OP_ELEM_ADDR=61; OP_COPY=62; OP_COPY_STR=63;
  OP_DUP=64; OP_DROP=65; OP_SWAP=66; OP_SHL=67; OP_SHR=68; OP_AADD=69;
  OP_CONST_L=70;
  OP_LADD=71; OP_LSUB=72; OP_LMUL=73; OP_LDIV=74; OP_LMOD=75; OP_LNEG=76; OP_LABS=77; OP_LODD=78;
  OP_LLT=79; OP_LLE=80; OP_LGT=81; OP_LGE=82; OP_LEQ=83; OP_LNE=84;
  OP_L2I=85; OP_JUMPTABLE=86; OP_DISPOSE=87; OP_PROCVAL=88; OP_CALLP=89;

  (* type kinds — match model.h *)
  TK_UNDEF=0; TK_NIL=1; TK_INT=2; TK_REAL=3; TK_BOOL=4; TK_CHAR=5; TK_SET=6;
  TK_ARRAY=7; TK_RECORD=8; TK_POINTER=9; TK_LONGINT=10; TK_PROC=11;

  (* object classes — match model.h *)
  CL_CONST=0; CL_VAR=1; CL_TYPE=2; CL_PROC=3; CL_MODULE=4;

  (* predefined proc ids — match parser.c *)
  PD_ABS=1; PD_ODD=2; PD_LEN=3; PD_ORD=4; PD_CHR=5; PD_ENTIER=6; PD_FLOOR=7;
  PD_NEW=20; PD_INC=21; PD_DEC=22; PD_INCL=23; PD_EXCL=24; PD_COPY=25;
  PD_HALT=26; PD_DISPOSE=27; PD_PROCV=28; PD_PROCC=29; PD_CAP=30;

  (* builtin module proc ids (module 255) — match parser.c *)
  B_OUT_INT=0; B_OUT_REAL=1; B_OUT_CHAR=2; B_OUT_STRING=3; B_OUT_LN=4;
  B_IN_INT=5; B_IN_REAL=6; B_IN_CHAR=7; B_IN_LINE=8; B_HALT=9;
  B_OUT_LONG=10; B_OUT_BYTE=11; B_IN_BYTE=12;
  B_FILES_OPEN=20; B_FILES_CREATE=21; B_FILES_CLOSE=22; B_FILES_READBYTE=23;
  B_FILES_WRITEBYTE=24; B_FILES_READ=25; B_FILES_WRITE=26; B_FILES_EOF=27;
  B_FILES_LENGTH=28; B_FILES_POS=29; B_FILES_SET=30; B_FILES_DELETE=31; B_FILES_EXISTS=32;
  B_SYS_BAND=40; B_SYS_BOR=41; B_SYS_BXOR=42; B_SYS_BNOT=43;
  B_SYS_LSH=44; B_SYS_ROT=45; B_SYS_BIT=46; B_SYS_ARGC=47; B_SYS_ARGV=48;
  B_SYS_TICKS=49; B_SYS_EXIT=50;
  B_SYS_L2I=51; B_SYS_REALBITS=52; B_SYS_BITSREAL=53; B_SYS_I2REAL=54;
  B_FFI_CALLC=80; B_FFI_LOADLIB=81; B_FFI_SYMBOL=82; B_FFI_FREELIB=83;
  B_FFI_CSTR=84; B_FFI_STR=85; B_FFI_MALLOC=86; B_FFI_FREE=87; B_FFI_PEEK=88; B_FFI_POKE=89;
  B_FFI_GETENV=90; B_FFI_EXEPATH=91;

  M_VAL=0; M_ADDR=1; M_VARARG=2;

  (* symbols — mirror of lexer.h (CASE labels must be local constants) *)
  S_EOF=0; S_IDENT=1; S_INT=2; S_REAL=3; S_CHAR=4; S_STRING=5;
  S_ARRAY=6; S_BEGIN=7; S_BY=8; S_CASE=9; S_CONST=10; S_DIV=11; S_DO=12; S_ELSE=13; S_ELSIF=14;
  S_END=15; S_FOR=16; S_HALT=17; S_IF=18; S_IMPORT=19; S_IN=20; S_IS=21; S_MOD=22; S_MODULE=23; S_NIL=24;
  S_OF=25; S_OR=26; S_POINTER=27; S_PROCEDURE=28; S_RECORD=29; S_REPEAT=30; S_RETURN=31; S_THEN=32;
  S_TO=33; S_TYPE=34; S_UNTIL=35; S_VAR=36; S_WHILE=37; S_WITH=38;
  S_ASSIGN=39; S_PLUS=40; S_MINUS=41; S_STAR=42; S_SLASH=43; S_AMP=44;
  S_TILDE=45; S_PIPE=46;
  S_EQ=47; S_NEQ=48; S_LT=49; S_LE=50; S_GT=51; S_GE=52;
  S_DOT=53; S_DOTDOT=54; S_COMMA=55; S_COLON=56; S_SEMI=57;
  S_LPAREN=58; S_RPAREN=59; S_LBRACK=60; S_RBRACK=61; S_CARET=62; S_LBRACE=63; S_RBRACE=64;
  S_FORWARD=65;

  MAXTYPE=1024; MAXPROC=512; MAXSTR=8192; MAXIMP=64; MAXDIM=8;
  CODESIZE=8388608;

TYPE
  Field = POINTER TO FieldDesc;
  Type  = POINTER TO TypeDesc;
  Obj   = POINTER TO ObjDesc;
  Proc  = POINTER TO ProcDesc;
  StrRef = POINTER TO ARRAY 4096 OF CHAR;

  DirRef = POINTER TO ARRAY 600 OF CHAR;

  LoadedMod = POINTER TO LoadedModDesc;
  LoadedModDesc = RECORD
    name: StrRef;
    types: POINTER TO ARRAY MAXTYPE OF Type;
    ntypes: INTEGER;
    members: Obj;
    modId: INTEGER
  END;

  FieldDesc = RECORD
    name: StrRef;
    typ: Type;
    offset: INTEGER;
    next: Field;
    raw: INTEGER   (* temp during .obc load: raw type index + 1 *)
  END;

  TypeDesc = RECORD
    kind: INTEGER;
    name: StrRef;
    isStringLit, anyCharArray, anyPointer, isOpen: BOOLEAN;
    elem: Type;                        (* ARRAY *)
    ndim: INTEGER; dims: ARRAY MAXDIM OF INTEGER; total: INTEGER;
    base: Type; fields: Field; nfields, payload, tag: INTEGER;  (* RECORD *)
    to: Type;                          (* POINTER *)
    params: Obj; nparams: INTEGER; result: Type;  (* PROC *)
    exported: BOOLEAN;
    stamp: INTEGER;
    raw: INTEGER     (* temp during .obc load *)
  END;

  ObjDesc = RECORD
    name: StrRef;
    cls: INTEGER;
    typ: Type;
    cval: LONGINT;                     (* CL_CONST *)
    level, offset, modId: INTEGER; isVarParam: BOOLEAN;  (* CL_VAR *)
    nparams: INTEGER; params: Obj; procIndex, exported: INTEGER;  (* CL_PROC *)
    members: Obj; builtin: BOOLEAN;    (* CL_MODULE *)
    defMod, defTypeIdx, builtinId: INTEGER;
    forward: BOOLEAN;
    next, nextGlobal, nextParam, nextConst: Obj
  END;

  CodeBlock = POINTER TO CodeBlockDesc;
  CodeBlockDesc = RECORD
    len: INTEGER;
    next: CodeBlock;
    data: ARRAY 4096 OF CHAR
  END;

  ProcDesc = RECORD
    name: StrRef;
    exported, isBody: BOOLEAN;
    nparams, nlocals, hasResult: INTEGER;
    result: Type;
    params: Obj;                       (* linked list via nextParam, in order *)
    codeHead, codeTail: CodeBlock;
    codeLen: INTEGER
  END;

VAR
  curLevel: INTEGER;
  scopeStack: ARRAY 64 OF Obj;
  scopeTop: INTEGER;
  typeInt, typeReal, typeBool, typeChar, typeSet, typeNil, typeLongint: Type;
  typeProc0, typeCharArrayAny, typeAnyPointer: Type;
  builtinOut, builtinIn, builtinFiles, builtinSystem: Obj;
  withShadows: ARRAY 64 OF Obj; nWithShadows: INTEGER;

  modName: ARRAY 64 OF CHAR;
  impNames: ARRAY MAXIMP OF StrRef; nimports: INTEGER;
  impCache: ARRAY MAXIMP OF LoadedMod; nImpCache: INTEGER;
  dummyR: StrRef; pa2: Obj;
  scratch: ARRAY 4096 OF CHAR;
  home: ARRAY 600 OF CHAR; ex: ARRAY 600 OF CHAR; pth: ARRAY 2048 OF CHAR;
  types: POINTER TO ARRAY MAXTYPE OF Type; ntypes: INTEGER;
  procs: POINTER TO ARRAY MAXPROC OF Proc; nprocs: INTEGER;
  globalsList: Obj; globalSize: INTEGER;
  constsList: Obj;
  strs: POINTER TO ARRAY MAXSTR OF StrRef; nstrings: INTEGER;
  curProc: Proc;
  gDesigHdr: INTEGER;
  allowOpenArray: BOOLEAN;
  tagCounter: INTEGER;
  gStamp: INTEGER;

  inPath, outPath, inDir: ARRAY 600 OF CHAR;
  outF: Files.File;
  msgbuf: ARRAY 256 OF CHAR;
  z1g: ARRAY 1 OF INTEGER;   (* zero-filled global, used as var-flag array *)
  dummyB: BOOLEAN;
  dummyT: Type;
  dummyP: Proc;
  z2g: ARRAY 2 OF INTEGER;

(* ---------- errors ---------- *)
PROCEDURE Err(m: ARRAY OF CHAR);
BEGIN
  Out.String("OC: "); Out.String(inPath); Out.String(":"); Out.Int(OCS.line, 0);
  Out.String(": "); Out.String(m); Out.Ln; SYSTEM.EXIT(1)
END Err;

PROCEDURE ErrN(m, n: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE (m[i] # 0X) & (i < 250) DO msgbuf[i] := m[i]; INC(i) END;
  msgbuf[i] := ' '; INC(i);
  j := 0; WHILE (n[j] # 0X) & (i < 254) DO msgbuf[i] := n[j]; INC(i); INC(j) END;
  msgbuf[i] := 0X; Err(msgbuf)
END ErrN;

(* ---------- string helpers ---------- *)
(* NB: never pass an inline array field of a record (t.name, o.name) as an open-array
   parameter — index it directly instead (see addrIsPayload note in docs/REPRISE.md). *)

PROCEDURE CopyStr(src, dst: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (src[i] # 0X) & (i < LEN(dst, 0) - 1) DO dst[i] := src[i]; INC(i) END;
  dst[i] := 0X
END CopyStr;

PROCEDURE NameEqO(VAR s: ARRAY OF CHAR; o: Obj): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (s[i] # 0X) & (o.name^[i] # 0X) & (s[i] = o.name^[i]) DO INC(i) END;
  RETURN (s[i] = 0X) & (o.name^[i] = 0X)
END NameEqO;

PROCEDURE NameEqT(VAR s: ARRAY OF CHAR; t: Type): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (s[i] # 0X) & (t.name^[i] # 0X) & (s[i] = t.name^[i]) DO INC(i) END;
  RETURN (s[i] = 0X) & (t.name^[i] = 0X)
END NameEqT;

PROCEDURE NameEqF(VAR s: ARRAY OF CHAR; f: Field): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (s[i] # 0X) & (f.name^[i] # 0X) & (s[i] = f.name^[i]) DO INC(i) END;
  RETURN (s[i] = 0X) & (f.name^[i] = 0X)
END NameEqF;

PROCEDURE NameEqS(a, b: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER; done, eq, ea, eb: BOOLEAN;
BEGIN
  (* NB: & is NOT short-circuit in this dialect — never index with a possibly-OOB i in a & chain *)
  i := 0; done := FALSE; eq := TRUE;
  WHILE ~done & eq DO
    IF (i >= LEN(a, 0)) OR (i >= LEN(b, 0)) THEN
      done := TRUE;
      IF i >= LEN(a, 0) THEN ea := TRUE ELSE ea := (a[i] = 0X) END;
      IF i >= LEN(b, 0) THEN eb := TRUE ELSE eb := (b[i] = 0X) END;
      eq := ea & eb
    ELSE
      IF a[i] # b[i] THEN eq := FALSE END;
      IF a[i] = 0X THEN done := TRUE END;
      INC(i)
    END
  END;
  RETURN eq
END NameEqS;

(* ---------- code emission (global arena; proc code = code[codeOfs .. codeOfs+codeLen)) ---------- *)
PROCEDURE Emit(b: LONGINT);
VAR cb: CodeBlock;
BEGIN
  cb := curProc.codeTail;
  IF (cb = NIL) OR (cb.len >= 4096) THEN
    NEW(cb); cb.len := 0; cb.next := NIL;
    IF curProc.codeHead = NIL THEN curProc.codeHead := cb ELSE curProc.codeTail.next := cb END;
    curProc.codeTail := cb
  END;
  cb.data[cb.len] := CHR(SYSTEM.L2I(b)); INC(cb.len); INC(curProc.codeLen)
END Emit;

PROCEDURE EmitU32Raw(v: LONGINT);
BEGIN
  Emit(SYSTEM.BAND(v, 255));
  Emit(SYSTEM.BAND(SYSTEM.LSH(v, -8), 255));
  Emit(SYSTEM.BAND(SYSTEM.LSH(v, -16), 255));
  Emit(SYSTEM.BAND(SYSTEM.LSH(v, -24), 255))
END EmitU32Raw;

PROCEDURE Emit32(op: INTEGER; v: LONGINT);
BEGIN Emit(op); EmitU32Raw(v) END Emit32;

PROCEDURE Emit64(op: INTEGER; v: LONGINT);
VAR i: INTEGER;
BEGIN
  Emit(op);
  i := 0;
  WHILE i < 8 DO Emit(SYSTEM.BAND(SYSTEM.LSH(v, -8*i), 255)); INC(i) END
END Emit64;

PROCEDURE Here(): INTEGER;
BEGIN RETURN curProc.codeLen
END Here;

PROCEDURE PatchByte(pos: INTEGER; b: LONGINT);
VAR cb: CodeBlock; p: INTEGER;
BEGIN
  cb := curProc.codeHead; p := pos;
  WHILE p >= cb.len DO p := p - cb.len; cb := cb.next END;
  cb.data[p] := CHR(SYSTEM.L2I(b))
END PatchByte;

PROCEDURE Patch32(pos: INTEGER; v: LONGINT);
BEGIN
  PatchByte(pos, SYSTEM.BAND(v, 255));
  PatchByte(pos+1, SYSTEM.BAND(SYSTEM.LSH(v, -8), 255));
  PatchByte(pos+2, SYSTEM.BAND(SYSTEM.LSH(v, -16), 255));
  PatchByte(pos+3, SYSTEM.BAND(SYSTEM.LSH(v, -24), 255))
END Patch32;

PROCEDURE EmitGlobalOp(op, mod, off: INTEGER);
BEGIN Emit(op); Emit(mod); EmitU32Raw(off) END EmitGlobalOp;

PROCEDURE EmitTypeOp(op, mod, idx: INTEGER);
BEGIN Emit(op); Emit(mod); EmitU32Raw(idx) END EmitTypeOp;

PROCEDURE EmitJump(op: INTEGER): INTEGER;
BEGIN Emit(op); EmitU32Raw(0); RETURN Here() - 4
END EmitJump;

PROCEDURE AllocTemp(): INTEGER;
BEGIN INC(curProc.nlocals); RETURN curProc.nlocals - 1
END AllocTemp;

(* ---------- lexer interface ---------- *)
PROCEDURE Expect(s: INTEGER);
VAR sn: ARRAY 32 OF CHAR;
BEGIN
  IF OCS.sym # s THEN
    OCS.SymName(s, sn); ErrN("syntax error: expected symbol", sn)
  END;
  OCS.Next
END Expect;

PROCEDURE Accept(s: INTEGER): BOOLEAN;
BEGIN IF OCS.sym = s THEN OCS.Next; RETURN TRUE ELSE RETURN FALSE END
END Accept;

PROCEDURE ReadIdent(VAR buf: ARRAY OF CHAR);
BEGIN
  IF OCS.sym # S_IDENT THEN Err("syntax error: expected identifier") END;
  CopyStr(OCS.name, buf);
  OCS.Next
END ReadIdent;

(* ---------- scope / symbol table ---------- *)
PROCEDURE ScopePush();
BEGIN
  IF scopeTop >= 63 THEN Err("scope overflow") END;
  INC(scopeTop); scopeStack[scopeTop] := NIL
END ScopePush;

PROCEDURE ScopePop();
BEGIN
  IF scopeTop < 0 THEN Err("scope underflow") END;
  DEC(scopeTop)
END ScopePop;

PROCEDURE NewObj(nm: ARRAY OF CHAR; cls: INTEGER): Obj;
VAR o: Obj;
BEGIN
  NEW(o);
  NEW(o.name);
  CopyStr(nm, o.name);
  o.cls := cls;
  o.typ := NIL; o.cval := 0;
  o.level := 0; o.offset := 0; o.modId := 0; o.isVarParam := FALSE;
  o.nparams := 0; o.params := NIL; o.procIndex := 0; o.exported := 0;
  o.members := NIL; o.builtin := FALSE;
  o.defMod := 0; o.defTypeIdx := 0; o.builtinId := 0;
  o.forward := FALSE;
  o.next := NIL; o.nextGlobal := NIL; o.nextParam := NIL; o.nextConst := NIL;
  RETURN o
END NewObj;

PROCEDURE LookupIn(list: Obj; VAR nm: ARRAY OF CHAR): Obj;
VAR o: Obj;
BEGIN
  o := list;
  WHILE o # NIL DO
    IF NameEqO(nm, o) THEN RETURN o END;
    o := o.next
  END;
  RETURN NIL
END LookupIn;

PROCEDURE Lookup(VAR nm: ARRAY OF CHAR): Obj;
VAR i: INTEGER; o: Obj;
BEGIN
  i := scopeTop;
  WHILE i >= 0 DO
    o := LookupIn(scopeStack[i], nm);
    IF o # NIL THEN RETURN o END;
    DEC(i)
  END;
  RETURN NIL
END Lookup;

PROCEDURE InsertObj(o: Obj);
BEGIN
  IF scopeTop < 0 THEN Err("no scope") END;
  IF LookupIn(scopeStack[scopeTop], o.name) # NIL THEN ErrN("duplicate identifier", o.name) END;
  o.next := scopeStack[scopeTop];
  scopeStack[scopeTop] := o
END InsertObj;

(* ---------- types ---------- *)
PROCEDURE NewType(kind: INTEGER): Type;
VAR t: Type;
BEGIN
  NEW(t);
  NEW(t.name);
  t.kind := kind;
  t.name^[0] := 0X;
  t.isStringLit := FALSE; t.anyCharArray := FALSE; t.anyPointer := FALSE; t.isOpen := FALSE;
  t.elem := NIL; t.ndim := 0; t.total := 1;
  t.base := NIL; t.fields := NIL; t.nfields := 0; t.payload := 0; t.tag := 0;
  t.to := NIL; t.params := NIL; t.nparams := 0; t.result := NIL;
  t.exported := FALSE;
  t.stamp := 0;
  RETURN t
END NewType;

PROCEDURE InitBasicTypes();
BEGIN
  typeInt := NewType(TK_INT); CopyStr("INTEGER", typeInt.name);
  typeReal := NewType(TK_REAL); CopyStr("REAL", typeReal.name);
  typeBool := NewType(TK_BOOL); CopyStr("BOOLEAN", typeBool.name);
  typeChar := NewType(TK_CHAR); CopyStr("CHAR", typeChar.name);
  typeSet := NewType(TK_SET); CopyStr("SET", typeSet.name);
  typeNil := NewType(TK_NIL); CopyStr("NIL", typeNil.name);
  typeLongint := NewType(TK_LONGINT); CopyStr("LONGINT", typeLongint.name);
  typeCharArrayAny := NewType(TK_ARRAY);
  typeCharArrayAny.elem := typeChar; typeCharArrayAny.ndim := 1;
  typeCharArrayAny.dims[0] := 1073741823; typeCharArrayAny.total := 1073741823;
  typeCharArrayAny.anyCharArray := TRUE;
  typeAnyPointer := NewType(TK_POINTER); CopyStr("ANYPOINTER", typeAnyPointer.name);
  typeAnyPointer.anyPointer := TRUE;
  typeProc0 := NewType(TK_PROC); CopyStr("PROCEDURE()", typeProc0.name)
END InitBasicTypes;

PROCEDURE TypeElemCells(e: Type): INTEGER;
BEGIN
  IF (e # NIL) & (e.kind = TK_RECORD) THEN RETURN e.payload ELSE RETURN 1 END
END TypeElemCells;

PROCEDURE TypeSizeCells(t: Type): INTEGER;
BEGIN
  IF (t # NIL) & (t.kind = TK_RECORD) THEN RETURN t.payload ELSE RETURN 1 END
END TypeSizeCells;

PROCEDURE TypeInlineCells(t: Type): INTEGER;
BEGIN
  IF t = NIL THEN RETURN 1 END;
  IF t.kind = TK_RECORD THEN RETURN t.payload END;
  IF (t.kind = TK_ARRAY) & ~t.isOpen THEN RETURN t.total * TypeElemCells(t.elem) END;
  RETURN 1
END TypeInlineCells;

PROCEDURE TypeEquals(a, b: Type): BOOLEAN;
VAR i: INTEGER; pa, pb: Obj; r: Type;
BEGIN
  IF a = b THEN RETURN TRUE END;
  IF (a = NIL) OR (b = NIL) THEN RETURN FALSE END;
  IF a.kind # b.kind THEN RETURN FALSE END;
  CASE a.kind OF
    TK_ARRAY:
      IF (a.ndim # b.ndim) OR (a.total # b.total) OR ~TypeEquals(a.elem, b.elem) THEN RETURN FALSE END;
      i := 0;
      WHILE i < a.ndim DO
        IF a.dims[i] # b.dims[i] THEN RETURN FALSE END;
        INC(i)
      END;
      RETURN TRUE
  | TK_POINTER:
      RETURN TypeEquals(a.to, b.to)
  | TK_PROC:
      IF a.nparams # b.nparams THEN RETURN FALSE END;
      pa := a.params; pb := b.params;
      WHILE (pa # NIL) & (pb # NIL) DO
        IF pa.isVarParam # pb.isVarParam THEN RETURN FALSE END;
        IF ~TypeEquals(pa.typ, pb.typ) THEN RETURN FALSE END;
        pa := pa.nextParam; pb := pb.nextParam
      END;
      IF (pa # NIL) OR (pb # NIL) THEN RETURN FALSE END;
      IF (a.result = NIL) # (b.result = NIL) THEN RETURN FALSE END;
      IF (a.result # NIL) & ~TypeEquals(a.result, b.result) THEN RETURN FALSE END;
      RETURN TRUE
  | TK_RECORD:
      RETURN a = b (* nominal *)
  ELSE
      RETURN TRUE (* basic singletons *)
  END
END TypeEquals;

PROCEDURE TypeAssignable(dst, src: Type): BOOLEAN;
VAR r: Type;
BEGIN
  IF (dst = NIL) OR (src = NIL) THEN RETURN FALSE END;
  IF TypeEquals(dst, src) THEN RETURN TRUE END;
  IF (dst.kind = TK_POINTER) & (src.kind = TK_NIL) THEN RETURN TRUE END;
  IF (dst.kind = TK_PROC) & (src.kind = TK_NIL) THEN RETURN TRUE END;
  IF (dst.kind = TK_LONGINT) & (src.kind = TK_INT) THEN RETURN TRUE END;
  IF (dst.kind = TK_REAL) & (src.kind = TK_INT) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & (src.kind = TK_ARRAY) & src.isStringLit &
     (dst.elem.kind = TK_CHAR) & (src.total <= dst.total) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & dst.anyCharArray & (src.kind = TK_ARRAY) &
     (src.elem.kind = TK_CHAR) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & dst.anyCharArray & (src.kind = TK_POINTER) &
     (src.to # NIL) & (src.to.kind = TK_ARRAY) & (src.to.elem.kind = TK_CHAR) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & dst.isOpen & (src.kind = TK_ARRAY) &
     TypeEquals(dst.elem, src.elem) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & dst.isOpen & (src.kind = TK_POINTER) &
     (src.to # NIL) & (src.to.kind = TK_ARRAY) & TypeEquals(dst.elem, src.to.elem) THEN RETURN TRUE END;
  IF (dst.kind = TK_ARRAY) & dst.isOpen & (dst.elem.kind = TK_CHAR) &
     (src.kind = TK_ARRAY) & src.isStringLit THEN RETURN TRUE END;
  IF (dst.kind = TK_POINTER) & (src.kind = TK_POINTER) &
     (dst.to.kind = TK_RECORD) & (src.to.kind = TK_RECORD) THEN
    r := src.to;
    WHILE r # NIL DO
      IF r = dst.to THEN RETURN TRUE END;
      IF r.kind = TK_RECORD THEN r := r.base ELSE r := NIL END
    END
  END;
  RETURN FALSE
END TypeAssignable;

PROCEDURE FindField(rec: Type; VAR fname: ARRAY OF CHAR): Field;
VAR r: Type; f: Field;
BEGIN
  r := rec;
  WHILE r # NIL DO
    f := r.fields;
    WHILE f # NIL DO
      IF NameEqF(fname, f) THEN RETURN f END;
      f := f.next
    END;
    IF r.kind = TK_RECORD THEN r := r.base ELSE r := NIL END
  END;
  RETURN NIL
END FindField;

PROCEDURE CompleteRecord(rec, base: Type; fields: Field; nf: INTEGER);
VAR f: Field; payload: INTEGER;
BEGIN
  rec.base := base; rec.fields := fields; rec.nfields := nf;
  IF base # NIL THEN payload := base.payload ELSE payload := 0 END;
  f := fields;
  WHILE f # NIL DO
    f.offset := payload;
    payload := payload + TypeInlineCells(f.typ);
    f := f.next
  END;
  rec.payload := payload;
  INC(tagCounter); rec.tag := tagCounter
END CompleteRecord;

PROCEDURE MkArrayType(elem: Type; nd: INTEGER; VAR dims: ARRAY OF INTEGER): Type;
VAR t: Type; i: INTEGER;
BEGIN
  t := NewType(TK_ARRAY);
  t.elem := elem; t.ndim := nd; t.total := 1;
  i := 0;
  WHILE i < nd DO
    IF dims[i] <= 0 THEN Err("array dimension must be positive") END;
    t.dims[i] := dims[i]; t.total := t.total * dims[i];
    INC(i)
  END;
  RETURN t
END MkArrayType;

PROCEDURE MkPointerType(to: Type): Type;
VAR t: Type;
BEGIN t := NewType(TK_POINTER); t.to := to; RETURN t END MkPointerType;

(* ---------- module type registry ---------- *)
PROCEDURE TypeIsRegistered(t: Type): BOOLEAN;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE i < ntypes DO
    IF types[i] = t THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END TypeIsRegistered;

PROCEDURE TypeIndex(t: Type): INTEGER;
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE i < ntypes DO
    IF types[i] = t THEN RETURN i END;
    INC(i)
  END;
  IF ntypes >= MAXTYPE THEN Err("too many types") END;
  types[ntypes] := t;
  INC(ntypes);
  RETURN ntypes - 1
END TypeIndex;

PROCEDURE RegisterTypeDeep(t: Type);
VAR fl: Field; pa: Obj;
BEGIN
  IF t = NIL THEN RETURN END;
  IF t.stamp = gStamp THEN RETURN END;
  t.stamp := gStamp;
  TypeIndex(t); (* appends BEFORE recursing: terminates on record<->pointer cycles *)
  CASE t.kind OF
    TK_ARRAY: RegisterTypeDeep(t.elem)
  | TK_RECORD:
      RegisterTypeDeep(t.base);
      fl := t.fields;
      WHILE fl # NIL DO RegisterTypeDeep(fl.typ); fl := fl.next END
  | TK_POINTER: RegisterTypeDeep(t.to)
  | TK_PROC:
      pa := t.params;
      WHILE pa # NIL DO RegisterTypeDeep(pa.typ); pa := pa.nextParam END;
      RegisterTypeDeep(t.result)
  ELSE
  END
END RegisterTypeDeep;

(* find (mod, idx) where type t is defined: own table first, else deep-register
   into own table (imported-module types are milestone 2; m stays 0) *)
PROCEDURE FindTypeRef(t: Type; VAR m, ix: INTEGER);
VAR i, j: INTEGER; lm: LoadedMod;
BEGIN
  i := 0;
  WHILE i < ntypes DO
    IF types[i] = t THEN m := 0; ix := i; RETURN END;
    INC(i)
  END;
  i := 0;
  WHILE i < nImpCache DO
    lm := impCache[i];
    j := 0;
    WHILE j < lm.ntypes DO
      IF lm.types[j] = t THEN m := lm.modId; ix := j; RETURN END;
      INC(j)
    END;
    INC(i)
  END;
  RegisterTypeDeep(t);
  m := 0; ix := TypeIndex(t)
END FindTypeRef;

(* ---------- predefined identifiers & builtin modules ---------- *)
PROCEDURE AppendParam(VAR head, tail: Obj; p: Obj);
BEGIN
  IF head = NIL THEN head := p ELSE tail.nextParam := p END;
  tail := p
END AppendParam;

PROCEDURE MkPredefProc(nm: ARRAY OF CHAR; id, nparams: INTEGER;
                       VAR ptypes: ARRAY OF Type; VAR vflags: ARRAY OF INTEGER): Obj;
VAR o, p: Obj; i: INTEGER; head, tail: Obj;
BEGIN
  o := NewObj(nm, CL_PROC);
  o.modId := -1;
  o.builtinId := id;
  o.nparams := nparams;
  head := NIL; tail := NIL;
  i := 0;
  WHILE i < nparams DO
    p := NewObj("", CL_VAR);
    p.typ := ptypes[i];
    p.isVarParam := (vflags[i] = 1);
    AppendParam(head, tail, p);
    INC(i)
  END;
  o.params := head;
  RETURN o
END MkPredefProc;

PROCEDURE InstallPredefined();
VAR o: Obj;
    z1: ARRAY 1 OF INTEGER; z2: ARRAY 2 OF INTEGER; z1v: ARRAY 1 OF INTEGER;
    t1: ARRAY 1 OF Type; t2: ARRAY 2 OF Type;
BEGIN
  o := NewObj("TRUE", CL_CONST); o.typ := typeBool; o.cval := 1; InsertObj(o);
  o := NewObj("FALSE", CL_CONST); o.typ := typeBool; o.cval := 0; InsertObj(o);
  o := NewObj("INTEGER", CL_TYPE); o.typ := typeInt; InsertObj(o);
  o := NewObj("REAL", CL_TYPE); o.typ := typeReal; InsertObj(o);
  o := NewObj("BOOLEAN", CL_TYPE); o.typ := typeBool; InsertObj(o);
  o := NewObj("CHAR", CL_TYPE); o.typ := typeChar; InsertObj(o);
  o := NewObj("SET", CL_TYPE); o.typ := typeSet; InsertObj(o);
  o := NewObj("LONGINT", CL_TYPE); o.typ := typeLongint; InsertObj(o);

  z1[0] := 0; z2[0] := 0; z2[1] := 0; z1v[0] := 1;
  t1[0] := typeInt;
  t2[0] := typeInt; t2[1] := typeInt;

  InsertObj(MkPredefProc("ABS", PD_ABS, 1, t1, z1));
  InsertObj(MkPredefProc("ODD", PD_ODD, 1, t1, z1));
  t2[0] := typeCharArrayAny;
  InsertObj(MkPredefProc("LEN", PD_LEN, 2, t2, z2));
  t1[0] := typeChar;
  InsertObj(MkPredefProc("ORD", PD_ORD, 1, t1, z1));
  t1[0] := typeInt;
  InsertObj(MkPredefProc("CHR", PD_CHR, 1, t1, z1));
  t1[0] := typeReal;
  InsertObj(MkPredefProc("ENTIER", PD_ENTIER, 1, t1, z1));
  InsertObj(MkPredefProc("FLOOR", PD_FLOOR, 1, t1, z1));
  t1[0] := typeCharArrayAny;
  InsertObj(MkPredefProc("NEW", PD_NEW, 1, t1, z1));
  t1[0] := typeAnyPointer;
  InsertObj(MkPredefProc("DISPOSE", PD_DISPOSE, 1, t1, z1v));
  t2[0] := typeInt; t2[1] := typeInt;
  InsertObj(MkPredefProc("INC", PD_INC, 2, t2, z2));
  InsertObj(MkPredefProc("DEC", PD_DEC, 2, t2, z2));
  t2[0] := typeSet; t2[1] := typeInt;
  InsertObj(MkPredefProc("INCL", PD_INCL, 2, t2, z2));
  InsertObj(MkPredefProc("EXCL", PD_EXCL, 2, t2, z2));
  t2[0] := typeCharArrayAny; t2[1] := typeCharArrayAny;
  InsertObj(MkPredefProc("COPY", PD_COPY, 2, t2, z2));
  t2[0] := typeInt; t2[1] := typeInt;
  InsertObj(MkPredefProc("HALT", PD_HALT, 1, t1, z1));
  t1[0] := typeChar;
  InsertObj(MkPredefProc("CAP", PD_CAP, 1, t1, z1));
  t1[0] := typeLongint;
  o := MkPredefProc("PROCV", PD_PROCV, 1, t1, z1); o.typ := typeProc0; InsertObj(o);
  t1[0] := typeProc0;
  o := MkPredefProc("PROCC", PD_PROCC, 1, t1, z1); o.typ := typeLongint; InsertObj(o)
END InstallPredefined;

PROCEDURE MkBuiltinProc(nm: ARRAY OF CHAR; id, nparams: INTEGER;
                        VAR ptypes: ARRAY OF Type; VAR vflags: ARRAY OF INTEGER): Obj;
VAR o, p: Obj; i: INTEGER; head, tail: Obj;
BEGIN
  o := NewObj(nm, CL_PROC);
  o.procIndex := id;
  o.level := 0;
  o.nparams := nparams;
  head := NIL; tail := NIL;
  i := 0;
  WHILE i < nparams DO
    p := NewObj("", CL_VAR);
    p.typ := ptypes[i];
    p.isVarParam := (vflags[i] = 1);
    AppendParam(head, tail, p);
    INC(i)
  END;
  o.params := head;
  RETURN o
END MkBuiltinProc;

(* append a member to a module's member list *)
PROCEDURE AppendMember(VAR head, tail: Obj; m: Obj);
BEGIN
  IF head = NIL THEN head := m ELSE tail.next := m END;
  tail := m
END AppendMember;

PROCEDURE MakeBuiltinModules();
VAR out, in, files, system: Obj;
    mh, mt: Obj;
    zv: ARRAY 2 OF INTEGER; vv: ARRAY 1 OF INTEGER;
    z3: ARRAY 3 OF INTEGER; z10: ARRAY 10 OF INTEGER;
    t1: ARRAY 1 OF Type; t2: ARRAY 2 OF Type; t3: ARRAY 3 OF Type; t10: ARRAY 10 OF Type;
    fileDesc, filePtr: Type;
    fh, fe: Field;
    o: Obj;
    i: INTEGER;
BEGIN
  zv[0] := 0; zv[1] := 0; vv[0] := 1;
  z3[0] := 0; z3[1] := 0; z3[2] := 0;
  i := 0; WHILE i < 10 DO z10[i] := 0; t10[i] := typeLongint; INC(i) END;
  t10[1] := typeInt;

  out := NewObj("Out", CL_MODULE); out.modId := 255; out.builtin := TRUE;
  mh := NIL; mt := NIL;
  t2[0] := typeInt; t2[1] := typeInt;
  AppendMember(mh, mt, MkBuiltinProc("Int", B_OUT_INT, 2, t2, zv));
  t2[0] := typeReal;
  AppendMember(mh, mt, MkBuiltinProc("Real", B_OUT_REAL, 2, t2, zv));
  t1[0] := typeChar;
  AppendMember(mh, mt, MkBuiltinProc("Char", B_OUT_CHAR, 1, t1, zv));
  t1[0] := typeCharArrayAny;
  AppendMember(mh, mt, MkBuiltinProc("String", B_OUT_STRING, 1, t1, zv));
  AppendMember(mh, mt, MkBuiltinProc("Ln", B_OUT_LN, 0, t1, zv));
  t2[0] := typeLongint;
  AppendMember(mh, mt, MkBuiltinProc("Long", B_OUT_LONG, 2, t2, zv));
  t1[0] := typeInt;
  AppendMember(mh, mt, MkBuiltinProc("Byte", B_OUT_BYTE, 1, t1, zv));
  out.members := mh; builtinOut := out;

  in := NewObj("In", CL_MODULE); in.modId := 255; in.builtin := TRUE;
  mh := NIL; mt := NIL;
  t1[0] := typeInt;
  AppendMember(mh, mt, MkBuiltinProc("Int", B_IN_INT, 1, t1, vv));
  t1[0] := typeReal;
  AppendMember(mh, mt, MkBuiltinProc("Real", B_IN_REAL, 1, t1, vv));
  t1[0] := typeChar;
  AppendMember(mh, mt, MkBuiltinProc("Char", B_IN_CHAR, 1, t1, vv));
  t1[0] := typeCharArrayAny;
  AppendMember(mh, mt, MkBuiltinProc("Line", B_IN_LINE, 1, t1, vv));
  t1[0] := typeInt;
  AppendMember(mh, mt, MkBuiltinProc("Byte", B_IN_BYTE, 1, t1, vv));
  in.members := mh; builtinIn := in;

  files := NewObj("Files", CL_MODULE); files.modId := 255; files.builtin := TRUE;
  mh := NIL; mt := NIL;
  fileDesc := NewType(TK_RECORD);
  NEW(fh); NEW(fh.name); CopyStr("handle", fh.name); fh.typ := typeLongint; fh.next := NIL;
  NEW(fe); NEW(fe.name); CopyStr("eof", fe.name); fe.typ := typeBool; fe.next := NIL;
  fh.next := fe;
  CompleteRecord(fileDesc, NIL, fh, 2);
  filePtr := MkPointerType(fileDesc);
  CopyStr("File", filePtr.name);
  o := NewObj("File", CL_TYPE); o.typ := filePtr;
  AppendMember(mh, mt, o);
  t1[0] := typeCharArrayAny;
  o := MkBuiltinProc("Open", B_FILES_OPEN, 1, t1, z1g); o.typ := filePtr; AppendMember(mh, mt, o);
  o := MkBuiltinProc("Create", B_FILES_CREATE, 1, t1, z1g); o.typ := filePtr; AppendMember(mh, mt, o);
  t1[0] := filePtr;
  AppendMember(mh, mt, MkBuiltinProc("Close", B_FILES_CLOSE, 1, t1, z1g));
  o := MkBuiltinProc("ReadByte", B_FILES_READBYTE, 1, t1, z1g); o.typ := typeInt; AppendMember(mh, mt, o);
  t2[0] := filePtr; t2[1] := typeInt;
  AppendMember(mh, mt, MkBuiltinProc("WriteByte", B_FILES_WRITEBYTE, 2, t2, zv));
  t3[0] := filePtr; t3[1] := typeCharArrayAny; t3[2] := typeInt;
  o := MkBuiltinProc("Read", B_FILES_READ, 3, t3, z3); o.typ := typeInt; AppendMember(mh, mt, o);
  o := MkBuiltinProc("Write", B_FILES_WRITE, 3, t3, z3); AppendMember(mh, mt, o);
  t1[0] := filePtr;
  o := MkBuiltinProc("Eof", B_FILES_EOF, 1, t1, z1g); o.typ := typeBool; AppendMember(mh, mt, o);
  o := MkBuiltinProc("Length", B_FILES_LENGTH, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  o := MkBuiltinProc("Pos", B_FILES_POS, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t2[0] := filePtr; t2[1] := typeLongint;
  AppendMember(mh, mt, MkBuiltinProc("Set", B_FILES_SET, 2, t2, zv));
  t1[0] := typeCharArrayAny;
  o := MkBuiltinProc("Delete", B_FILES_DELETE, 1, t1, z1g); o.typ := typeBool; AppendMember(mh, mt, o);
  o := MkBuiltinProc("Exists", B_FILES_EXISTS, 1, t1, z1g); o.typ := typeBool; AppendMember(mh, mt, o);
  files.members := mh; builtinFiles := files;

  system := NewObj("SYSTEM", CL_MODULE); system.modId := 255; system.builtin := TRUE;
  mh := NIL; mt := NIL;
  t2[0] := typeLongint; t2[1] := typeLongint;
  o := MkBuiltinProc("BAND", B_SYS_BAND, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  o := MkBuiltinProc("BOR", B_SYS_BOR, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  o := MkBuiltinProc("BXOR", B_SYS_BXOR, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  t1[0] := typeLongint;
  o := MkBuiltinProc("BNOT", B_SYS_BNOT, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t2[0] := typeLongint; t2[1] := typeLongint;
  o := MkBuiltinProc("LSH", B_SYS_LSH, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  o := MkBuiltinProc("ROT", B_SYS_ROT, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  o := MkBuiltinProc("BIT", B_SYS_BIT, 2, t2, zv); o.typ := typeBool; AppendMember(mh, mt, o);
  o := MkBuiltinProc("ARGC", B_SYS_ARGC, 0, t1, z1g); o.typ := typeInt; AppendMember(mh, mt, o);
  t2[0] := typeInt; t2[1] := typeCharArrayAny; zv[0] := 0; zv[1] := 1;
  AppendMember(mh, mt, MkBuiltinProc("ARGV", B_SYS_ARGV, 2, t2, zv));
  zv[0] := 0; zv[1] := 0;
  o := MkBuiltinProc("TICKS", B_SYS_TICKS, 0, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t1[0] := typeInt;
  o := MkBuiltinProc("EXIT", B_SYS_EXIT, 1, t1, z1g); AppendMember(mh, mt, o);
  t1[0] := typeLongint;
  o := MkBuiltinProc("L2I", B_SYS_L2I, 1, t1, z1g); o.typ := typeInt; AppendMember(mh, mt, o);
  t1[0] := typeReal;
  o := MkBuiltinProc("REALBITS", B_SYS_REALBITS, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t1[0] := typeLongint;
  o := MkBuiltinProc("BITSREAL", B_SYS_BITSREAL, 1, t1, z1g); o.typ := typeReal; AppendMember(mh, mt, o);
  t1[0] := typeInt;
  o := MkBuiltinProc("I2REAL", B_SYS_I2REAL, 1, t1, z1g); o.typ := typeReal; AppendMember(mh, mt, o);
  o := MkBuiltinProc("CALLC", B_FFI_CALLC, 10, t10, z10); o.typ := typeLongint; AppendMember(mh, mt, o);
  t1[0] := typeCharArrayAny;
  o := MkBuiltinProc("LOADLIB", B_FFI_LOADLIB, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t2[0] := typeLongint; t2[1] := typeCharArrayAny;
  o := MkBuiltinProc("SYMBOL", B_FFI_SYMBOL, 2, t2, zv); o.typ := typeLongint; AppendMember(mh, mt, o);
  t1[0] := typeLongint;
  AppendMember(mh, mt, MkBuiltinProc("FREELIB", B_FFI_FREELIB, 1, t1, z1g));
  t1[0] := typeCharArrayAny;
  o := MkBuiltinProc("CSTR", B_FFI_CSTR, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t2[0] := typeLongint; t2[1] := typeCharArrayAny; zv[0] := 0; zv[1] := 1;
  AppendMember(mh, mt, MkBuiltinProc("STR", B_FFI_STR, 2, t2, zv));
  t1[0] := typeLongint;
  o := MkBuiltinProc("MALLOC", B_FFI_MALLOC, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  AppendMember(mh, mt, MkBuiltinProc("FREE", B_FFI_FREE, 1, t1, z1g));
  o := MkBuiltinProc("PEEK", B_FFI_PEEK, 1, t1, z1g); o.typ := typeLongint; AppendMember(mh, mt, o);
  t2[0] := typeLongint; t2[1] := typeLongint; zv[0] := 0; zv[1] := 0;
  AppendMember(mh, mt, MkBuiltinProc("POKE", B_FFI_POKE, 2, t2, zv));
  t2[0] := typeCharArrayAny; t2[1] := typeCharArrayAny; zv[0] := 0; zv[1] := 1;
  o := MkBuiltinProc("GETENV", B_FFI_GETENV, 2, t2, zv); o.typ := typeBool; AppendMember(mh, mt, o);
  t1[0] := typeCharArrayAny;
  o := MkBuiltinProc("EXEPATH", B_FFI_EXEPATH, 1, t1, vv); o.typ := typeInt; AppendMember(mh, mt, o);
  system.members := mh; builtinSystem := system
END MakeBuiltinModules;

(* ---------- forward declarations for the mutually recursive parser ---------- *)
PROCEDURE ParseExpression(): Type; FORWARD;
PROCEDURE ParseSimpleExpr(): Type; FORWARD;
PROCEDURE ParseTerm(): Type; FORWARD;
PROCEDURE ParseFactor(): Type; FORWARD;
PROCEDURE ParseStatements(); FORWARD;
PROCEDURE ParseStatement(); FORWARD;
PROCEDURE IsEndSym(): BOOLEAN; FORWARD;
PROCEDURE ParseDesignator(mode: INTEGER; o: Obj; mod: INTEGER): Type; FORWARD;
PROCEDURE ReadFirstIdent(VAR mod: INTEGER): Obj; FORWARD;
PROCEDURE ParseType(): Type; FORWARD;
PROCEDURE ParseQualType(): Type; FORWARD;
PROCEDURE ParseConstExpr(VAR t: Type): LONGINT; FORWARD;
PROCEDURE ParseArgsList(params: Obj; nm: ARRAY OF CHAR); FORWARD;
PROCEDURE ParseCallArgs(proc: Obj; mod: INTEGER); FORWARD;
PROCEDURE EmitCall(proc: Obj; mod: INTEGER); FORWARD;
PROCEDURE TryEmitProcValue(pt: Type): BOOLEAN; FORWARD;
PROCEDURE ParseDeclarations(isGlobal: INTEGER); FORWARD;
PROCEDURE InstallImport(real, alias: ARRAY OF CHAR); FORWARD;
PROCEDURE StrLenA(s: ARRAY OF CHAR): INTEGER; FORWARD;
PROCEDURE AppendStr(VAR dst: ARRAY OF CHAR; suf: ARRAY OF CHAR); FORWARD;
PROCEDURE ParseProcDecl(); FORWARD;

(* ---------- constant expressions ---------- *)
PROCEDURE FoldIntOp(op: INTEGER; a, b: LONGINT): LONGINT;
VAR q, r: LONGINT;
BEGIN
  CASE op OF
    S_PLUS: RETURN a + b
  | S_MINUS: RETURN a - b
  | S_STAR: RETURN a * b
  | S_DIV:
      q := a DIV b; r := a MOD b;
      IF (r # 0) & ((r < 0) # (b < 0)) THEN q := q - 1 END;
      RETURN q
  | S_MOD:
      r := a MOD b;
      IF (r # 0) & ((r < 0) # (b < 0)) THEN r := r + b END;
      RETURN r
  ELSE Err("bad const op"); RETURN 0
  END
END FoldIntOp;

PROCEDURE ConstFactor(VAR t: Type): LONGINT; FORWARD;

PROCEDURE ConstTerm(VAR t: Type): LONGINT;
VAR v, v2: LONGINT; op: INTEGER; t2: Type; d, d2, r: REAL;
BEGIN
  v := ConstFactor(t);
  WHILE (OCS.sym = S_STAR) OR (OCS.sym = S_SLASH) OR (OCS.sym = S_DIV) OR
        (OCS.sym = S_MOD) OR (OCS.sym = S_AMP) DO
    op := OCS.sym; OCS.Next;
    v2 := ConstFactor(t2);
    IF op = S_AMP THEN v := SYSTEM.BAND(v, v2); t := typeBool
    ELSIF op = S_SLASH THEN
      IF (t # NIL) & (t = typeReal) THEN d := SYSTEM.BITSREAL(v) ELSE d := SYSTEM.I2REAL(SYSTEM.L2I(v)) END;
      IF t2 = typeReal THEN d2 := SYSTEM.BITSREAL(v2) ELSE d2 := SYSTEM.I2REAL(SYSTEM.L2I(v2)) END;
      v := SYSTEM.REALBITS(d / d2); t := typeReal
    ELSE
      IF (t = typeSet) & (t2 = typeSet) THEN
        IF op = S_STAR THEN v := SYSTEM.BAND(v, v2)
        ELSIF op = S_MINUS THEN v := SYSTEM.BAND(v, SYSTEM.BNOT(v2))
        ELSE v := SYSTEM.BOR(v, v2) END
      ELSIF (t = typeReal) OR (t2 = typeReal) THEN
        IF t = typeReal THEN d := SYSTEM.BITSREAL(v) ELSE d := SYSTEM.I2REAL(SYSTEM.L2I(v)) END;
        IF t2 = typeReal THEN d2 := SYSTEM.BITSREAL(v2) ELSE d2 := SYSTEM.I2REAL(SYSTEM.L2I(v2)) END;
        CASE op OF
          S_PLUS: r := d + d2
        | S_MINUS: r := d - d2
        | S_STAR: r := d * d2
        ELSE r := d / d2
        END;
        v := SYSTEM.REALBITS(r); t := typeReal
      ELSE
        v := FoldIntOp(op, v, v2);
        IF (t = typeLongint) OR (t2 = typeLongint) THEN t := typeLongint ELSE t := typeInt END
      END
    END
  END;
  RETURN v
END ConstTerm;

PROCEDURE ConstSimple(VAR t: Type): LONGINT;
VAR neg: BOOLEAN; v, v2: LONGINT; op: INTEGER; t2: Type; d, d2: REAL;
BEGIN
  neg := FALSE;
  IF OCS.sym = S_PLUS THEN OCS.Next
  ELSIF OCS.sym = S_MINUS THEN neg := TRUE; OCS.Next END;
  v := ConstTerm(t);
  IF neg THEN
    IF t = typeReal THEN v := SYSTEM.REALBITS(-SYSTEM.BITSREAL(v)) ELSE v := -v END
  END;
  WHILE (OCS.sym = S_PLUS) OR (OCS.sym = S_MINUS) OR (OCS.sym = S_OR) DO
    op := OCS.sym; OCS.Next;
    v2 := ConstTerm(t2);
    IF op = S_OR THEN v := SYSTEM.BAND(v, v2); t := typeBool
    ELSIF (t = typeReal) OR (t2 = typeReal) THEN
      IF t = typeReal THEN d := SYSTEM.BITSREAL(v) ELSE d := SYSTEM.I2REAL(SYSTEM.L2I(v)) END;
      IF t2 = typeReal THEN d2 := SYSTEM.BITSREAL(v2) ELSE d2 := SYSTEM.I2REAL(SYSTEM.L2I(v2)) END;
      IF op = S_PLUS THEN v := SYSTEM.REALBITS(d + d2) ELSE v := SYSTEM.REALBITS(d - d2) END;
      t := typeReal
    ELSIF (t = typeSet) & (t2 = typeSet) THEN
      IF op = S_PLUS THEN v := SYSTEM.BOR(v, v2) ELSE v := SYSTEM.BAND(v, SYSTEM.BNOT(v2)) END
    ELSE
      v := FoldIntOp(op, v, v2);
      IF (t = typeLongint) OR (t2 = typeLongint) THEN t := typeLongint ELSE t := typeInt END
    END
  END;
  RETURN v
END ConstSimple;

PROCEDURE ConstFactor(VAR t: Type): LONGINT;
VAR v, a, b, i: LONGINT; o: Obj; n: ARRAY 64 OF CHAR; s: LONGINT; t2: Type;
BEGIN
  IF OCS.sym = S_INT THEN
    v := OCS.ival; OCS.Next;
    IF (v > 2147483647) OR (v < -2147483648) THEN t := typeLongint; RETURN v END;
    t := typeInt; RETURN v
  END;
  IF OCS.sym = S_REAL THEN t := typeReal; v := SYSTEM.REALBITS(OCS.rval); OCS.Next; RETURN v END;
  IF OCS.sym = S_CHAR THEN t := typeChar; v := OCS.cval; OCS.Next; RETURN v END;
  IF OCS.sym = S_NIL THEN t := typeNil; OCS.Next; RETURN 0 END;
  IF OCS.sym = S_LPAREN THEN
    OCS.Next; v := ConstSimple(t); Expect(S_RPAREN); RETURN v
  END;
  IF OCS.sym = S_TILDE THEN
    OCS.Next; t := typeBool;
    IF ConstFactor(t) = 0 THEN RETURN 1 ELSE RETURN 0 END
  END;
  IF OCS.sym = S_LBRACE THEN
    OCS.Next; s := 0; t := typeSet;
    IF OCS.sym # S_RBRACE THEN
      REPEAT
        a := ConstSimple(t);
        IF Accept(S_DOTDOT) THEN
          b := ConstSimple(t2);
          i := a;
          WHILE (i <= b) & (i < 32) DO s := SYSTEM.BOR(s, SYSTEM.LSH(1, SYSTEM.L2I(i))); i := i + 1 END
        ELSE
          IF (a >= 0) & (a < 32) THEN s := SYSTEM.BOR(s, SYSTEM.LSH(1, SYSTEM.L2I(a))) END
        END
      UNTIL ~Accept(S_COMMA)
    END;
    Expect(S_RBRACE);
    RETURN s
  END;
  IF OCS.sym = S_IDENT THEN
    CopyStr(OCS.name, n); OCS.Next;
    o := Lookup(n);
    IF (o = NIL) OR (o.cls # CL_CONST) THEN ErrN("is not a constant", n) END;
    t := o.typ;
    RETURN o.cval
  END;
  Err("expected constant expression");
  RETURN 0
END ConstFactor;

PROCEDURE ParseConstExpr(VAR t: Type): LONGINT;
VAR v, v2: LONGINT; op: INTEGER; t2: Type; r: BOOLEAN; a, b: REAL;
BEGIN
  v := ConstSimple(t);
  IF (OCS.sym = S_EQ) OR (OCS.sym = S_NEQ) OR (OCS.sym = S_LT) OR
     (OCS.sym = S_LE) OR (OCS.sym = S_GT) OR (OCS.sym = S_GE) THEN
    op := OCS.sym; OCS.Next;
    v2 := ConstSimple(t2);
    r := FALSE;
    IF (t = typeReal) OR (t2 = typeReal) THEN
      IF t = typeReal THEN a := SYSTEM.BITSREAL(v) ELSE a := SYSTEM.I2REAL(SYSTEM.L2I(v)) END;
      IF t2 = typeReal THEN b := SYSTEM.BITSREAL(v2) ELSE b := SYSTEM.I2REAL(SYSTEM.L2I(v2)) END;
      CASE op OF
        S_EQ: r := a = b
      | S_NEQ: r := a # b
      | S_LT: r := a < b
      | S_LE: r := a <= b
      | S_GT: r := a > b
      | S_GE: r := a >= b
      END
    ELSE
      CASE op OF
        S_EQ: r := v = v2
      | S_NEQ: r := v # v2
      | S_LT: r := v < v2
      | S_LE: r := v <= v2
      | S_GT: r := v > v2
      | S_GE: r := v >= v2
      END
    END;
    t := typeBool;
    IF r THEN RETURN 1 ELSE RETURN 0 END
  END;
  RETURN v
END ParseConstExpr;

(* ---------- types ---------- *)
PROCEDURE ParseQualType(): Type;
VAR n1, n2: ARRAY 64 OF CHAR; o: Obj;
BEGIN
  ReadIdent(n1);
  o := Lookup(n1);
  IF (o # NIL) & (o.cls = CL_MODULE) THEN
    Expect(S_DOT);
    ReadIdent(n2);
    o := LookupIn(o.members, n2)
  END;
  IF (o = NIL) OR (o.cls # CL_TYPE) THEN ErrN("is not a type", n1) END;
  RETURN o.typ
END ParseQualType;

PROCEDURE ParseType(): Type;
VAR t, e, base, to, rt, rec: Type;
    dims: ARRAY MAXDIM OF INTEGER; nd, i, nn: INTEGER;
    v: LONGINT; dt: Type;
    fnames: ARRAY 16 OF StrRef;
    fields, fl, tail: Field;
    nf: INTEGER;
    n: ARRAY 64 OF CHAR;
    o, pa: Obj;
    isVar: BOOLEAN;
    savedAllow: BOOLEAN;
    head, ptail: Obj;
    pt: Type;
BEGIN
  ptail := NIL;
  IF OCS.sym = S_ARRAY THEN
    OCS.Next;
    IF allowOpenArray & (OCS.sym = S_OF) THEN
      OCS.Next;
      e := ParseType();
      t := NewType(TK_ARRAY);
      t.elem := e; t.ndim := 1; t.dims[0] := 1073741823; t.total := 1073741823;
      t.isOpen := TRUE;
      RETURN t
    END;
    nd := 0;
    REPEAT
      v := ParseConstExpr(dt);
      IF (dt # typeInt) OR (v <= 0) OR (v > 100000000) THEN Err("bad array dimension") END;
      IF nd >= MAXDIM THEN Err("too many dimensions") END;
      dims[nd] := SYSTEM.L2I(v); INC(nd)
    UNTIL ~Accept(S_COMMA);
    Expect(S_OF);
    e := ParseType();
    RETURN MkArrayType(e, nd, dims)
  END;
  IF OCS.sym = S_RECORD THEN
    OCS.Next;
    base := NIL;
    IF Accept(S_LPAREN) THEN
      base := ParseQualType();
      IF base.kind # TK_RECORD THEN Err("base type must be a record") END;
      Expect(S_RPAREN)
    END;
    fields := NIL; tail := NIL; nf := 0;
    WHILE OCS.sym = S_IDENT DO
      nn := 0;
      REPEAT
        IF nn >= 16 THEN Err("too many fields in one declaration") END;
        NEW(fnames[nn]); CopyStr(OCS.name, fnames[nn]); INC(nn); OCS.Next
      UNTIL ~Accept(S_COMMA);
      Expect(S_COLON);
      t := ParseType();
      dummyB := Accept(S_SEMI);
      i := 0;
      WHILE i < nn DO
        NEW(fl);
        NEW(fl.name); CopyStr(fnames[i], fl.name);
        fl.typ := t; fl.next := NIL;
        IF fields = NIL THEN fields := fl ELSE tail.next := fl END;
        tail := fl;
        INC(nf); INC(i)
      END
    END;
    Expect(S_END);
    rec := NewType(TK_RECORD);
    CompleteRecord(rec, base, fields, nf);
    RETURN rec
  END;
  IF OCS.sym = S_POINTER THEN
    OCS.Next;
    Expect(S_TO);
    IF OCS.sym = S_ARRAY THEN
      to := ParseType();
      IF (to.kind # TK_ARRAY) OR to.isOpen THEN Err("pointer base must be a fixed array or record") END;
      RETURN MkPointerType(to)
    END;
    ReadIdent(n);
    o := Lookup(n);
    IF (o # NIL) & (o.cls = CL_TYPE) THEN
      to := o.typ
    ELSE
      to := NewType(TK_RECORD);
      CopyStr(n, to.name);
      o := NewObj(n, CL_TYPE);
      o.typ := to;
      InsertObj(o)
    END;
    IF (o # NIL) & (o.cls = CL_MODULE) THEN Err("module-qualified pointer not supported here") END;
    IF (to.kind # TK_RECORD) & (to.kind # TK_ARRAY) THEN Err("pointer base must be a record or array") END;
    IF (to.kind = TK_ARRAY) & to.isOpen THEN Err("pointer to open array not allowed") END;
    RETURN MkPointerType(to)
  END;
  IF OCS.sym = S_PROCEDURE THEN
    OCS.Next;
    pt := NewType(TK_PROC);
    IF Accept(S_LPAREN) THEN
      IF OCS.sym # S_RPAREN THEN
        REPEAT
          isVar := Accept(S_VAR);
          nn := 0;
          REPEAT
            IF nn >= 16 THEN Err("too many parameter names in procedure type") END;
            NEW(fnames[nn]); CopyStr(OCS.name, fnames[nn]); INC(nn); OCS.Next
          UNTIL ~Accept(S_COMMA);
          Expect(S_COLON);
          savedAllow := allowOpenArray;
          allowOpenArray := TRUE;
          t := ParseType();
          allowOpenArray := savedAllow;
          i := 0;
          WHILE i < nn DO
            pa := NewObj(fnames[i], CL_VAR);
            pa.typ := t;
            pa.isVarParam := isVar;
            AppendParam(pt.params, ptail, pa);
            INC(pt.nparams);
            INC(i)
          END
        UNTIL ~Accept(S_SEMI)
      END;
      Expect(S_RPAREN)
    END;
    IF Accept(S_COLON) THEN pt.result := ParseType() END;
    RETURN pt
  END;
  RETURN ParseQualType()
END ParseType;

(* ---------- declarations ---------- *)
PROCEDURE ParseConstDecl();
VAR n: ARRAY 64 OF CHAR; exported: BOOLEAN; t: Type; v: LONGINT; o: Obj;
BEGIN
  WHILE OCS.sym = S_IDENT DO
    CopyStr(OCS.name, n); OCS.Next;
    exported := Accept(S_STAR);
    Expect(S_EQ);
    v := ParseConstExpr(t);
    Expect(S_SEMI);
    o := NewObj(n, CL_CONST);
    o.typ := t; o.cval := v;
    IF exported THEN o.exported := 1 END;
    o.nextConst := constsList; constsList := o;
    InsertObj(o)
  END
END ParseConstDecl;

PROCEDURE ParseTypeDecl();
VAR n: ARRAY 64 OF CHAR; exported: BOOLEAN; existing, o: Obj; t, base, ft: Type;
    fnames: ARRAY 16 OF StrRef; fields, fl, tail: Field; nf, nn, i: INTEGER;
    idx: INTEGER;
BEGIN
  WHILE OCS.sym = S_IDENT DO
    CopyStr(OCS.name, n); OCS.Next;
    exported := Accept(S_STAR);
    dummyB := Accept(S_MINUS); (* read-only marker ignored *)
    Expect(S_EQ);
    existing := Lookup(n);
    IF (OCS.sym = S_RECORD) & (existing # NIL) & (existing.cls = CL_TYPE) &
       (existing.typ.kind = TK_RECORD) & (existing.typ.fields = NIL) & (existing.typ.payload = 0) THEN
      (* complete the placeholder *)
      t := existing.typ;
      OCS.Next; (* RECORD *)
      base := NIL;
      IF Accept(S_LPAREN) THEN
        base := ParseQualType();
        Expect(S_RPAREN)
      END;
      fields := NIL; tail := NIL; nf := 0;
      WHILE OCS.sym = S_IDENT DO
        nn := 0;
        REPEAT
          IF nn >= 16 THEN Err("too many fields in one declaration") END;
          NEW(fnames[nn]); CopyStr(OCS.name, fnames[nn]); INC(nn); OCS.Next
        UNTIL ~Accept(S_COMMA);
        Expect(S_COLON);
        ft := ParseType();
        dummyB := Accept(S_SEMI);
        i := 0;
        WHILE i < nn DO
          NEW(fl); NEW(fl.name); CopyStr(fnames[i], fl.name);
          fl.typ := ft; fl.next := NIL;
          IF fields = NIL THEN fields := fl ELSE tail.next := fl END;
          tail := fl; INC(nf); INC(i)
        END
      END;
      Expect(S_END);
      CompleteRecord(t, base, fields, nf);
      CopyStr(n, t.name)
    ELSE
      t := ParseType();
      CopyStr(n, t.name);
      o := NewObj(n, CL_TYPE);
      o.typ := t;
      IF exported THEN o.exported := 1 END;
      InsertObj(o)
    END;
    idx := TypeIndex(t);
    types[idx].exported := exported;
    Expect(S_SEMI)
  END
END ParseTypeDecl;

PROCEDURE ParseVarDecl(isGlobal: INTEGER);
VAR names: ARRAY 16 OF StrRef; nn, i, sz, m, ix: INTEGER; exported: BOOLEAN;
    t: Type; o: Obj;
BEGIN
  WHILE OCS.sym = S_IDENT DO
    nn := 0;
    REPEAT
      IF nn >= 16 THEN Err("too many variables in one declaration") END;
      NEW(names[nn]); CopyStr(OCS.name, names[nn]); INC(nn); OCS.Next
    UNTIL ~Accept(S_COMMA);
    exported := Accept(S_STAR);
    Expect(S_COLON);
    t := ParseType();
    Expect(S_SEMI);
    i := 0;
    WHILE i < nn DO
      o := NewObj(names[i], CL_VAR);
      o.typ := t;
      IF exported THEN o.exported := 1 END;
      sz := TypeSizeCells(t);
      IF isGlobal = 1 THEN
        o.level := 0;
        o.offset := globalSize;
        globalSize := globalSize + sz;
        o.modId := 0;
        o.nextGlobal := globalsList;
        globalsList := o
      ELSE
        o.level := curLevel;
        o.offset := curProc.nlocals;
        curProc.nlocals := curProc.nlocals + sz;
        IF t.kind = TK_ARRAY THEN
          FindTypeRef(t, m, ix);
          EmitTypeOp(OP_ALLOC_ARRAY, m, ix);
          Emit32(OP_STORE_LOCAL, o.offset)
        END
      END;
      InsertObj(o);
      INC(i)
    END
  END
END ParseVarDecl;

PROCEDURE AddProc(nm: ARRAY OF CHAR; exported, isBody: INTEGER): Proc;
VAR p: Proc;
BEGIN
  IF nprocs >= MAXPROC THEN Err("too many procs") END;
  NEW(p);
  NEW(p.name); CopyStr(nm, p.name);
  IF exported = 1 THEN p.exported := TRUE ELSE p.exported := FALSE END;
  IF isBody = 1 THEN p.isBody := TRUE ELSE p.isBody := FALSE END;
  p.nparams := 0; p.nlocals := 0; p.hasResult := 0;
  p.result := NIL; p.params := NIL;
  p.codeHead := NIL; p.codeTail := NIL; p.codeLen := 0;
  procs[nprocs] := p;
  INC(nprocs);
  RETURN p
END AddProc;

PROCEDURE ParseProcDecl();
VAR pname: ARRAY 64 OF CHAR; exported: BOOLEAN; po, existing, pa, ptail: Obj;
    pIdx: INTEGER; reused: BOOLEAN;
    i, nn: INTEGER;
    isVar: BOOLEAN; savedAllow: BOOLEAN;
    pt: Type;
    names: ARRAY 16 OF StrRef;
    savedProc: Proc;
BEGIN
  Expect(S_PROCEDURE);
  ReadIdent(pname);
  exported := Accept(S_STAR);
  existing := LookupIn(scopeStack[scopeTop], pname);
  reused := (existing # NIL) & (existing.cls = CL_PROC) & existing.forward;
  savedProc := curProc;
  ptail := NIL;
  IF reused THEN
    po := existing;
    po.forward := FALSE;
    IF exported THEN po.exported := 1 END;
    pIdx := po.procIndex;
    procs[pIdx].nparams := 0;
    procs[pIdx].nlocals := 0;
    procs[pIdx].codeHead := NIL; procs[pIdx].codeTail := NIL; procs[pIdx].codeLen := 0;
    po.params := NIL
  ELSE
    po := NewObj(pname, CL_PROC);
    po.level := curLevel;
    IF exported THEN po.exported := 1 END;
    po.procIndex := nprocs;
    InsertObj(po);
    pIdx := nprocs;
    dummyP := AddProc(pname, 0, 0)
  END;
  curProc := procs[pIdx];
  INC(curLevel);
  ScopePush();
  (* parameters *)
  IF Accept(S_LPAREN) THEN
    IF OCS.sym # S_RPAREN THEN
      REPEAT
        isVar := Accept(S_VAR);
        nn := 0;
        REPEAT
          IF nn >= 16 THEN Err("too many parameter names") END;
          NEW(names[nn]); CopyStr(OCS.name, names[nn]); INC(nn); OCS.Next
        UNTIL ~Accept(S_COMMA);
        Expect(S_COLON);
        savedAllow := allowOpenArray;
        allowOpenArray := TRUE;
        pt := ParseType();
        allowOpenArray := savedAllow;
        i := 0;
        WHILE i < nn DO
          pa := NewObj(names[i], CL_VAR);
          pa.typ := pt;
          pa.isVarParam := isVar;
          pa.level := curLevel;
          pa.offset := curProc.nlocals; INC(curProc.nlocals);
          AppendParam(po.params, ptail, pa);
          INC(curProc.nparams);
          INC(po.nparams);
          InsertObj(pa);
          INC(i)
        END
      UNTIL ~Accept(S_SEMI)
    END;
    Expect(S_RPAREN)
  END;
  procs[pIdx].params := po.params;
  IF Accept(S_COLON) THEN
    curProc.hasResult := 1;
    curProc.result := ParseType();
    po.typ := curProc.result
  END;
  Expect(S_SEMI);
  po.nparams := curProc.nparams;
  IF Accept(S_FORWARD) THEN
    po.forward := TRUE;
    Expect(S_SEMI);
    ScopePop();
    DEC(curLevel);
    curProc := savedProc;
    RETURN
  END;
  ParseDeclarations(0);
  curProc := procs[pIdx]; (* procs array stable here (pointers), but re-fetch anyway *)
  IF Accept(S_BEGIN) THEN ParseStatements() END;
  Emit(OP_RET);
  Expect(S_END);
  IF OCS.sym = S_IDENT THEN OCS.Next END;
  Expect(S_SEMI);
  ScopePop();
  DEC(curLevel);
  curProc := savedProc
END ParseProcDecl;

PROCEDURE ParseDeclarations(isGlobal: INTEGER);
BEGIN
  WHILE TRUE DO
    IF OCS.sym = S_CONST THEN OCS.Next; ParseConstDecl()
    ELSIF OCS.sym = S_TYPE THEN OCS.Next; ParseTypeDecl()
    ELSIF OCS.sym = S_VAR THEN OCS.Next; ParseVarDecl(isGlobal)
    ELSIF OCS.sym = S_PROCEDURE THEN ParseProcDecl()
    ELSE RETURN END
  END
END ParseDeclarations;

(* ---------- imports ---------- *)
PROCEDURE ParseImports();
VAR alias, real: ARRAY 64 OF CHAR;
BEGIN
  REPEAT
    ReadIdent(alias);
    CopyStr(alias, real);
    IF Accept(S_ASSIGN) THEN ReadIdent(real) END;
    InstallImport(real, alias)
  UNTIL ~Accept(S_COMMA);
  Expect(S_SEMI)
END ParseImports;

(* ---------- designators ---------- *)
PROCEDURE ReadFirstIdent(VAR mod: INTEGER): Obj;
VAR n1, n2: ARRAY 64 OF CHAR; o: Obj;
BEGIN
  ReadIdent(n1);
  o := Lookup(n1);
  IF o = NIL THEN ErrN("undefined identifier", n1) END;
  mod := 0;
  IF o.cls = CL_MODULE THEN
    mod := o.modId;
    Expect(S_DOT);
    ReadIdent(n2);
    o := LookupIn(o.members, n2);
    IF o = NIL THEN ErrN("not exported by module", n1) END
  END;
  RETURN o
END ReadFirstIdent;

(* st: 0 = stack top is a value, 1 = stack top is a tagged address of storage *)
PROCEDURE ParseDesignator(mode: INTEGER; o: Obj; mod: INTEGER): Type;
VAR t: Type; st, hdr, h, nd, k, m, ix: INTEGER;
    addrIsPayload, done, more: BOOLEAN;
    fname: ARRAY 64 OF CHAR;
    fl: Field;
    it, rt, rec: Type;
BEGIN
  t := o.typ;
  st := 0;
  hdr := 0;
  gDesigHdr := 0;
  IF o.cls = CL_CONST THEN
    IF t.kind = TK_REAL THEN Emit64(OP_CONST_R, o.cval)
    ELSIF t.kind = TK_LONGINT THEN Emit64(OP_CONST_L, o.cval)
    ELSE Emit32(OP_CONST_I, o.cval) END;
    RETURN t
  END;
  IF o.cls # CL_VAR THEN ErrN("is not a variable", o.name) END;
  IF o.level = 0 THEN
    IF mode = M_VAL THEN
      IF t.kind = TK_RECORD THEN EmitGlobalOp(OP_ADDR_GLOBAL, mod, o.offset); st := 1
      ELSE EmitGlobalOp(OP_LOAD_GLOBAL, mod, o.offset); st := 0 END
    ELSE EmitGlobalOp(OP_ADDR_GLOBAL, mod, o.offset); st := 1 END
  ELSE
    IF o.isVarParam THEN
      Emit32(OP_ADDR_LOCAL, (curLevel - o.level) * 65536 + o.offset);
      Emit(OP_LOAD_AT); (* effective address passed by caller *)
      st := 1;
      IF mode = M_VAL THEN
        IF (t.kind = TK_ARRAY) OR (t.kind = TK_POINTER) THEN Emit(OP_LOAD_AT)
        ELSIF t.kind = TK_RECORD THEN (* value is the record addr already *)
        ELSE Emit(OP_LOAD_AT) END;
        st := 0
      END
    ELSE
      IF mode = M_VAL THEN
        IF t.kind = TK_RECORD THEN Emit32(OP_ADDR_LOCAL, (curLevel - o.level) * 65536 + o.offset); st := 1
        ELSE Emit32(OP_LOAD_LOCAL, (curLevel - o.level) * 65536 + o.offset); st := 0 END
      ELSE Emit32(OP_ADDR_LOCAL, (curLevel - o.level) * 65536 + o.offset); st := 1 END
    END
  END;
  (* selectors *)
  addrIsPayload := FALSE;
  done := FALSE;
  WHILE ~done DO
    IF OCS.sym = S_DOT THEN
      OCS.Next;
      ReadIdent(fname);
      h := hdr;
      IF (t.kind = TK_POINTER) & (t.to.kind = TK_RECORD) THEN
        IF st = 1 THEN Emit(OP_LOAD_AT) END;
        Emit(OP_TO_ADDR);
        st := 1;
        t := t.to;
        h := 2
      END;
      IF t.kind # TK_RECORD THEN Err("field selection on non-record") END;
      fl := FindField(t, fname);
      IF fl = NIL THEN ErrN("no field", fname) END;
      Emit32(OP_CONST_I, h + fl.offset);
      Emit(OP_AADD);
      st := 1;
      t := fl.typ;
      hdr := 0;
      addrIsPayload := (t.kind = TK_ARRAY)
    ELSIF OCS.sym = S_CARET THEN
      OCS.Next;
      IF t.kind # TK_POINTER THEN Err("dereference of non-pointer") END;
      IF st = 1 THEN Emit(OP_LOAD_AT) END;
      IF t.to.kind = TK_RECORD THEN Emit(OP_TO_ADDR); st := 1; hdr := 2
      ELSE st := 0 END;
      t := t.to
    ELSIF OCS.sym = S_LPAREN THEN
      (* type guard in designator: p(T) *)
      OCS.Next;
      rt := ParseQualType();
      Expect(S_RPAREN);
      IF rt.kind = TK_POINTER THEN rec := rt.to ELSE rec := rt END;
      IF (t.kind # TK_POINTER) OR (rec.kind # TK_RECORD) THEN Err("bad type guard") END;
      IF st = 1 THEN Emit(OP_LOAD_AT) END;
      FindTypeRef(rec, m, ix);
      EmitTypeOp(OP_CHECKTYPE, m, ix);
      IF rt.kind = TK_POINTER THEN t := rt ELSE t := MkPointerType(rec) END;
      st := 0
    ELSIF OCS.sym = S_LBRACK THEN
      IF (t.kind = TK_POINTER) & (t.to # NIL) & (t.to.kind = TK_ARRAY) THEN
        IF st = 1 THEN Emit(OP_LOAD_AT); st := 0 END;
        t := t.to
      END;
      IF t.kind # TK_ARRAY THEN Err("indexing non-array") END;
      IF (st = 1) & ~addrIsPayload THEN Emit(OP_LOAD_AT); st := 0 END;
      nd := t.ndim;
      Emit32(OP_CONST_I, 0); (* accumulator *)
      k := 0;
      WHILE OCS.sym = S_LBRACK DO
        OCS.Next;
        more := TRUE;
        WHILE more DO
          IF k >= nd THEN Err("too many indices") END;
          it := ParseExpression();
          IF it # typeInt THEN Err("index must be INTEGER") END;
          Emit(OP_SWAP);
          Emit32(OP_CONST_I, t.dims[k]);
          Emit(OP_IMUL);
          Emit(OP_SWAP);
          Emit(OP_IADD);
          INC(k);
          more := Accept(S_COMMA)
        END;
        Expect(S_RBRACK)
      END;
      IF k # nd THEN Err("wrong number of indices") END;
      IF t.elem.kind = TK_RECORD THEN
        Emit32(OP_CONST_I, TypeElemCells(t.elem));
        Emit(OP_IMUL)
      END;
      IF addrIsPayload THEN Emit(OP_AADD) ELSE Emit(OP_ELEM_ADDR) END;
      st := 1;
      t := t.elem;
      hdr := 0;
      addrIsPayload := (t.kind = TK_ARRAY)
    ELSE done := TRUE END
  END;
  (* final mode conversion *)
  gDesigHdr := hdr;
  IF mode = M_VAL THEN
    IF st = 1 THEN
      IF t.kind # TK_RECORD THEN Emit(OP_LOAD_AT) END;
      st := 0
    END
  ELSIF mode = M_ADDR THEN
    IF t.kind = TK_ARRAY THEN
      IF ~addrIsPayload THEN
        IF st = 1 THEN Emit(OP_LOAD_AT) END;
        Emit(OP_TO_ADDR);
        Emit32(OP_CONST_I, t.ndim + 2);
        Emit(OP_AADD)
      END
    ELSIF t.kind = TK_RECORD THEN
      Emit32(OP_CONST_I, hdr);
      Emit(OP_AADD)
    END
  END;
  RETURN t
END ParseDesignator;

(* ---------- expressions ---------- *)
PROCEDURE IsIntLike(t: Type): BOOLEAN;
BEGIN RETURN (t = typeInt) OR (t = typeLongint) END IsIntLike;

PROCEDURE EmitI2FTop(t: Type);
BEGIN IF t = typeInt THEN Emit(OP_I2F) END END EmitI2FTop;

PROCEDURE EmitI2FBelow(t: Type);
BEGIN IF t = typeInt THEN Emit(OP_SWAP); Emit(OP_I2F); Emit(OP_SWAP) END END EmitI2FBelow;

PROCEDURE EmitRelation(op: INTEGER; a, b: Type);
VAR mixed, isReal, isNum, isLong: BOOLEAN;
BEGIN
  mixed := ((a = typeReal) & (b = typeInt)) OR ((a = typeInt) & (b = typeReal));
  IF mixed THEN
    IF a = typeInt THEN Emit(OP_SWAP); Emit(OP_I2F); Emit(OP_SWAP) ELSE Emit(OP_I2F) END
  END;
  isReal := ((a = typeReal) & (b = typeReal)) OR mixed;
  isNum := ((a = typeInt) & (b = typeInt)) OR ((a = typeChar) & (b = typeChar));
  isLong := IsIntLike(a) & IsIntLike(b) & ((a = typeLongint) OR (b = typeLongint));
  CASE op OF
    S_EQ: IF isReal THEN Emit(OP_FEQ) ELSE Emit(OP_EQ) END
  | S_NEQ: IF isReal THEN Emit(OP_FNE) ELSE Emit(OP_NE) END
  | S_LT: IF isReal THEN Emit(OP_FLT) ELSIF isLong THEN Emit(OP_LLT) ELSIF isNum THEN Emit(OP_ILT) ELSE Err("bad operands for <") END
  | S_LE: IF isReal THEN Emit(OP_FLE) ELSIF isLong THEN Emit(OP_LLE) ELSIF isNum THEN Emit(OP_ILE) ELSE Err("bad operands for <=") END
  | S_GT: IF isReal THEN Emit(OP_FGT) ELSIF isLong THEN Emit(OP_LGT) ELSIF isNum THEN Emit(OP_IGT) ELSE Err("bad operands for >") END
  | S_GE: IF isReal THEN Emit(OP_FGE) ELSIF isLong THEN Emit(OP_LGE) ELSIF isNum THEN Emit(OP_IGE) ELSE Err("bad operands for >=") END
  | S_IN:
      IF (((a = typeInt) OR (a = typeChar)) & (b = typeSet)) THEN Emit(OP_SET_MEMBER)
      ELSE Err("IN requires INTEGER/CHAR and SET") END
  ELSE Err("IS handled separately")
  END
END EmitRelation;

PROCEDURE ParseExpression(): Type;
VAR t, t2, rt, rec: Type; op: INTEGER; m, ix: INTEGER;
BEGIN
  t := ParseSimpleExpr();
  IF (OCS.sym = S_EQ) OR (OCS.sym = S_NEQ) OR (OCS.sym = S_LT) OR
     (OCS.sym = S_LE) OR (OCS.sym = S_GT) OR (OCS.sym = S_GE) OR
     (OCS.sym = S_IN) OR (OCS.sym = S_IS) THEN
    op := OCS.sym; OCS.Next;
    IF op = S_IS THEN
      rt := ParseQualType();
      IF rt.kind = TK_POINTER THEN rec := rt.to ELSE rec := rt END;
      IF (t.kind # TK_POINTER) OR (rec.kind # TK_RECORD) THEN Err("IS requires pointer and record type") END;
      FindTypeRef(rec, m, ix);
      EmitTypeOp(OP_ISTYPE, m, ix);
      RETURN typeBool
    END;
    t2 := ParseSimpleExpr();
    IF (op # S_IN) & ~(((IsIntLike(t) & IsIntLike(t2)) OR ((t = typeReal) & (t2 = typeReal)) OR
          ((t = typeReal) & (t2 = typeInt)) OR ((t = typeInt) & (t2 = typeReal)) OR
          ((t = typeChar) & (t2 = typeChar)) OR
          ((t = typeBool) & (t2 = typeBool) & ((op = S_EQ) OR (op = S_NEQ))) OR
          ((t = typeSet) & (t2 = typeSet) & ((op = S_EQ) OR (op = S_NEQ))) OR
          (((t.kind = TK_POINTER) OR (t.kind = TK_NIL)) & ((t2.kind = TK_POINTER) OR (t2.kind = TK_NIL)) & ((op = S_EQ) OR (op = S_NEQ))) OR
          (((t.kind = TK_PROC) OR (t.kind = TK_NIL)) & ((t2.kind = TK_PROC) OR (t2.kind = TK_NIL)) & ((op = S_EQ) OR (op = S_NEQ))))) THEN
      Err("incompatible types in comparison")
    END;
    EmitRelation(op, t, t2);
    t := typeBool
  END;
  RETURN t
END ParseExpression;

PROCEDURE ParseSimpleExpr(): Type;
VAR neg: BOOLEAN; t, t2: Type; op: INTEGER;
BEGIN
  neg := FALSE;
  IF OCS.sym = S_PLUS THEN OCS.Next
  ELSIF OCS.sym = S_MINUS THEN neg := TRUE; OCS.Next END;
  t := ParseTerm();
  IF neg THEN
    IF t = typeInt THEN Emit(OP_INEG)
    ELSIF t = typeLongint THEN Emit(OP_LNEG)
    ELSIF t = typeReal THEN Emit(OP_FNEG)
    ELSE Err("unary minus on non-number") END
  END;
  WHILE (OCS.sym = S_PLUS) OR (OCS.sym = S_MINUS) OR (OCS.sym = S_OR) DO
    op := OCS.sym; OCS.Next;
    t2 := ParseTerm();
    IF op = S_OR THEN
      IF (t # typeBool) OR (t2 # typeBool) THEN Err("OR requires BOOLEAN") END;
      Emit(OP_OR)
    ELSIF IsIntLike(t) & IsIntLike(t2) & ((t = typeLongint) OR (t2 = typeLongint)) THEN
      IF op = S_PLUS THEN Emit(OP_LADD) ELSE Emit(OP_LSUB) END
    ELSIF (t = typeInt) & (t2 = typeInt) THEN
      IF op = S_PLUS THEN Emit(OP_IADD) ELSE Emit(OP_ISUB) END
    ELSIF (t = typeReal) & (t2 = typeReal) THEN
      IF op = S_PLUS THEN Emit(OP_FADD) ELSE Emit(OP_FSUB) END
    ELSIF ((t = typeReal) & (t2 = typeInt)) OR ((t = typeInt) & (t2 = typeReal)) THEN
      IF t = typeInt THEN EmitI2FBelow(t) ELSE EmitI2FTop(t2) END;
      IF op = S_PLUS THEN Emit(OP_FADD) ELSE Emit(OP_FSUB) END
    ELSIF (t = typeSet) & (t2 = typeSet) THEN
      IF op = S_PLUS THEN Emit(OP_SET_UNION) ELSE Emit(OP_SET_DIFF) END
    ELSE Err("incompatible types in expression") END;
    IF (t = typeReal) OR (t2 = typeReal) THEN t := typeReal
    ELSIF (t = typeSet) & (t2 = typeSet) THEN t := typeSet
    ELSIF IsIntLike(t) & IsIntLike(t2) & ((t = typeLongint) OR (t2 = typeLongint)) THEN t := typeLongint END
  END;
  RETURN t
END ParseSimpleExpr;

PROCEDURE ParseTerm(): Type;
VAR t, t2: Type; op: INTEGER;
BEGIN
  t := ParseFactor();
  WHILE (OCS.sym = S_STAR) OR (OCS.sym = S_SLASH) OR (OCS.sym = S_DIV) OR
        (OCS.sym = S_MOD) OR (OCS.sym = S_AMP) DO
    op := OCS.sym; OCS.Next;
    t2 := ParseFactor();
    IF op = S_AMP THEN
      IF (t # typeBool) OR (t2 # typeBool) THEN Err("& requires BOOLEAN") END;
      Emit(OP_AND)
    ELSIF op = S_STAR THEN
      IF IsIntLike(t) & IsIntLike(t2) & ((t = typeLongint) OR (t2 = typeLongint)) THEN Emit(OP_LMUL)
      ELSIF (t = typeInt) & (t2 = typeInt) THEN Emit(OP_IMUL)
      ELSIF (t = typeReal) & (t2 = typeReal) THEN Emit(OP_FMUL)
      ELSIF ((t = typeReal) & (t2 = typeInt)) OR ((t = typeInt) & (t2 = typeReal)) THEN
        IF t = typeInt THEN EmitI2FBelow(t) ELSE EmitI2FTop(t2) END;
        Emit(OP_FMUL)
      ELSIF (t = typeSet) & (t2 = typeSet) THEN Emit(OP_SET_INTER)
      ELSE Err("bad operands for *") END;
      IF (t = typeReal) OR (t2 = typeReal) THEN t := typeReal
      ELSIF (t = typeLongint) OR (t2 = typeLongint) THEN t := typeLongint END
    ELSIF op = S_SLASH THEN
      IF (t = typeLongint) OR (t2 = typeLongint) THEN Err("/ on LONGINT: convert to REAL explicitly") END;
      IF (t # typeReal) & (t # typeInt) THEN Err("/ requires REAL operands") END;
      IF (t2 # typeReal) & (t2 # typeInt) THEN Err("/ requires REAL operands") END;
      IF (t = typeInt) & (t2 = typeInt) THEN Emit(OP_I2F); EmitI2FBelow(typeInt)
      ELSIF t = typeInt THEN EmitI2FBelow(t)
      ELSIF t2 = typeInt THEN Emit(OP_I2F) END;
      Emit(OP_FDIV);
      t := typeReal
    ELSE
      IF IsIntLike(t) & IsIntLike(t2) & ((t = typeLongint) OR (t2 = typeLongint)) THEN
        IF op = S_DIV THEN Emit(OP_LDIV) ELSE Emit(OP_LMOD) END;
        t := typeLongint
      ELSE
        IF (t # typeInt) OR (t2 # typeInt) THEN Err("DIV/MOD require INTEGER or LONGINT") END;
        IF op = S_DIV THEN Emit(OP_IDIV) ELSE Emit(OP_IMOD) END
      END
    END
  END;
  RETURN t
END ParseTerm;

(* ---------- factors ---------- *)
PROCEDURE AddString(VAR s: ARRAY OF CHAR): INTEGER;
VAR r: StrRef; i: INTEGER;
BEGIN
  IF nstrings >= MAXSTR THEN Err("too many strings") END;
  NEW(r);
  i := 0;
  WHILE (s[i] # 0X) & (i < 4095) DO r^[i] := s[i]; INC(i) END;
  r^[i] := 0X;
  strs[nstrings] := r;
  INC(nstrings);
  RETURN nstrings - 1
END AddString;

PROCEDURE StringLitType(len: INTEGER): Type;
VAR dims: ARRAY 1 OF INTEGER; t: Type;
BEGIN
  dims[0] := len + 1;
  t := MkArrayType(typeChar, 1, dims);
  t.isStringLit := TRUE;
  RETURN t
END StringLitType;

PROCEDURE ParseFactor(): Type;
VAR t, t2, rt, rec, pt: Type;
    o: Obj; mod, m2: INTEGER;
    idx, dim, tlo, thi, L, jz, back, jm, tmp: INTEGER;
    dt: Type; dv: LONGINT;
BEGIN
  CASE OCS.sym OF
    S_INT:
      IF (OCS.ival > 2147483647) OR (OCS.ival < -2147483648) THEN
        Emit64(OP_CONST_L, OCS.ival); OCS.Next; RETURN typeLongint
      END;
      Emit32(OP_CONST_I, OCS.ival); OCS.Next; RETURN typeInt
  | S_REAL:
      Emit64(OP_CONST_R, SYSTEM.REALBITS(OCS.rval)); OCS.Next; RETURN typeReal
  | S_CHAR:
      Emit32(OP_CONST_I, OCS.cval); OCS.Next; RETURN typeChar
  | S_STRING:
      idx := AddString(OCS.sval);
      Emit32(OP_CONST_S, idx);
      OCS.Next;
      RETURN StringLitType(OCS.slen)
  | S_NIL:
      Emit32(OP_CONST_I, 0); OCS.Next; RETURN typeNil
  | S_LBRACE:
      (* set constructor *)
      OCS.Next;
      Emit32(OP_CONST_I, 0); (* accumulator *)
      IF OCS.sym # S_RBRACE THEN
        REPEAT
          t := ParseSimpleExpr();
          IF (t # typeInt) & (t # typeChar) THEN Err("set element must be INTEGER or CHAR") END;
          IF Accept(S_DOTDOT) THEN
            t2 := ParseSimpleExpr();
            IF (t2 # typeInt) & (t2 # typeChar) THEN Err("set range bound must be INTEGER or CHAR") END;
            tlo := AllocTemp(); thi := AllocTemp();
            Emit32(OP_STORE_LOCAL, thi);
            Emit32(OP_STORE_LOCAL, tlo);
            L := Here();
            Emit32(OP_LOAD_LOCAL, tlo);
            Emit32(OP_LOAD_LOCAL, thi);
            Emit(OP_ILE);
            jz := EmitJump(OP_JZ);
            Emit(OP_DUP);
            Emit32(OP_LOAD_LOCAL, tlo);
            Emit32(OP_CONST_I, 1);
            Emit(OP_SWAP);
            Emit(OP_SHL);
            Emit(OP_SET_UNION);
            Emit32(OP_ADDR_LOCAL, tlo);
            Emit(OP_DUP); Emit(OP_LOAD_AT);
            Emit32(OP_CONST_I, 1); Emit(OP_IADD); Emit(OP_STORE_AT);
            back := EmitJump(OP_JMP);
            Patch32(back, L);
            Patch32(jz, Here())
          ELSE
            Emit32(OP_CONST_I, 1);
            Emit(OP_SWAP);
            Emit(OP_SHL);
            Emit(OP_SET_UNION)
          END
        UNTIL ~Accept(S_COMMA)
      END;
      Expect(S_RBRACE);
      RETURN typeSet
  | S_LPAREN:
      OCS.Next;
      t := ParseExpression();
      Expect(S_RPAREN);
      RETURN t
  | S_TILDE:
      OCS.Next;
      t := ParseFactor();
      IF t # typeBool THEN Err("~ requires BOOLEAN") END;
      Emit(OP_NOT);
      RETURN typeBool
  | S_IDENT:
      o := ReadFirstIdent(mod);
      IF o.modId = -1 THEN
        CASE o.builtinId OF
          PD_ABS:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t = typeInt THEN Emit(OP_IABS)
            ELSIF t = typeLongint THEN Emit(OP_LABS)
            ELSIF t = typeReal THEN Emit(OP_FABS)
            ELSE Err("ABS requires number") END;
            RETURN t
        | PD_ODD:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t = typeLongint THEN Emit(OP_LODD)
            ELSIF t = typeInt THEN Emit(OP_IODD)
            ELSE Err("ODD requires INTEGER or LONGINT") END;
            RETURN typeBool
        | PD_LEN:
            Expect(S_LPAREN);
            o := ReadFirstIdent(m2);
            t := ParseDesignator(M_VAL, o, m2);
            IF (t.kind = TK_POINTER) & (t.to # NIL) & (t.to.kind = TK_ARRAY) THEN t := t.to END;
            IF t.kind # TK_ARRAY THEN Err("LEN requires array") END;
            dim := 0;
            IF Accept(S_COMMA) THEN
              dv := ParseConstExpr(dt);
              IF (dt # typeInt) OR (dv < 0) OR (dv >= t.ndim) THEN Err("bad LEN dimension") END;
              dim := SYSTEM.L2I(dv)
            END;
            Expect(S_RPAREN);
            Emit32(OP_LEN, dim);
            RETURN typeInt
        | PD_ORD:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeChar THEN Err("ORD requires CHAR") END;
            RETURN typeInt
        | PD_CHR:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeInt THEN Err("CHR requires INTEGER") END;
            RETURN typeChar
        | PD_ENTIER:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeReal THEN Err("ENTIER requires REAL") END;
            Emit(OP_F2I);
            RETURN typeInt
        | PD_FLOOR:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeReal THEN Err("FLOOR requires REAL") END;
            Emit(OP_FFLOOR);
            RETURN typeInt
        | PD_PROCV:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeLongint THEN Err("PROCV requires LONGINT") END;
            RETURN typeProc0
        | PD_PROCC:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF (t = NIL) OR (t.kind # TK_PROC) THEN Err("PROCC requires a procedure value") END;
            RETURN typeLongint
        | PD_CAP:
            Expect(S_LPAREN); t := ParseExpression(); Expect(S_RPAREN);
            IF t # typeChar THEN Err("CAP requires CHAR") END;
            tmp := AllocTemp();
            Emit32(OP_STORE_LOCAL, tmp);
            Emit32(OP_LOAD_LOCAL, tmp);
            Emit32(OP_CONST_I, ORD('a'));
            Emit(OP_IGE);
            Emit32(OP_LOAD_LOCAL, tmp);
            Emit32(OP_CONST_I, ORD('z'));
            Emit(OP_ILE);
            Emit(OP_AND);
            jz := EmitJump(OP_JZ);
            Emit32(OP_LOAD_LOCAL, tmp);
            Emit32(OP_CONST_I, 32);
            Emit(OP_ISUB);
            jm := EmitJump(OP_JMP);
            Patch32(jz, Here());
            Emit32(OP_LOAD_LOCAL, tmp);
            Patch32(jm, Here());
            RETURN typeChar
        ELSE ErrN("cannot be used in an expression", o.name)
        END
      END;
      IF o.cls = CL_PROC THEN
        IF o.typ = NIL THEN ErrN("is not a function", o.name) END;
        IF OCS.sym = S_LPAREN THEN ParseCallArgs(o, mod)
        ELSIF o.nparams = 0 THEN EmitCall(o, mod)
        ELSE ErrN("expected ( in call to", o.name) END;
        RETURN o.typ
      END;
      IF (o.cls = CL_VAR) & (o.typ # NIL) & (o.typ.kind = TK_PROC) & (OCS.sym = S_LPAREN) THEN
        pt := o.typ;
        ParseArgsList(pt.params, o.name);
        dummyT := ParseDesignator(M_VAL, o, mod);
        Emit(OP_CALLP);
        IF pt.result = NIL THEN ErrN("procedure variable without result", o.name) END;
        RETURN pt.result
      END;
      t := ParseDesignator(M_VAL, o, mod);
      IF OCS.sym = S_LPAREN THEN
        OCS.Next;
        rt := ParseQualType();
        Expect(S_RPAREN);
        IF rt.kind = TK_POINTER THEN rec := rt.to ELSE rec := rt END;
        IF (t.kind # TK_POINTER) OR (rec.kind # TK_RECORD) THEN Err("bad type guard") END;
        FindTypeRef(rec, m2, idx);
        EmitTypeOp(OP_CHECKTYPE, m2, idx);
        IF rt.kind = TK_POINTER THEN t := rt ELSE t := MkPointerType(rec) END
      END;
      RETURN t
  ELSE Err("expected factor")
  END;
  RETURN typeInt
END ParseFactor;

(* ---------- procedure calls ---------- *)
PROCEDURE EmitCall(proc: Obj; mod: INTEGER);
VAR steps: LONGINT;
BEGIN
  steps := 0;
  IF mod # 255 THEN steps := curLevel - proc.level END;
  Emit(OP_CALL);
  EmitU32Raw(mod);
  EmitU32Raw(proc.procIndex);
  EmitU32Raw(steps)
END EmitCall;

PROCEDURE ProcSigMatches(pt: Type; proc: Obj): BOOLEAN;
VAR pa, pb: Obj;
BEGIN
  IF (pt = NIL) OR (pt.kind # TK_PROC) THEN RETURN FALSE END;
  IF (proc = NIL) OR (proc.cls # CL_PROC) OR (proc.modId = -1) THEN RETURN FALSE END;
  IF proc.nparams # pt.nparams THEN RETURN FALSE END;
  pa := pt.params; pb := proc.params;
  WHILE (pa # NIL) & (pb # NIL) DO
    IF pa.isVarParam # pb.isVarParam THEN RETURN FALSE END;
    IF ~TypeEquals(pa.typ, pb.typ) THEN RETURN FALSE END;
    pa := pa.nextParam; pb := pb.nextParam
  END;
  IF (pa # NIL) OR (pb # NIL) THEN RETURN FALSE END;
  IF (pt.result = NIL) # (proc.typ = NIL) THEN RETURN FALSE END;
  IF (pt.result # NIL) & ~TypeEquals(pt.result, proc.typ) THEN RETURN FALSE END;
  RETURN TRUE
END ProcSigMatches;

(* Try to parse "Ident" or "Module.Ident" as a procedure reference and emit OP_PROCVAL.
   Returns TRUE if consumed, FALSE with the lexer restored otherwise. *)
PROCEDURE TryEmitProcValue(pt: Type): BOOLEAN;
VAR ls: OCS.LexState; mod: INTEGER; o: Obj; steps: LONGINT;
BEGIN
  IF OCS.sym # S_IDENT THEN RETURN FALSE END;
  OCS.Save(ls);
  o := ReadFirstIdent(mod);
  IF (o.cls = CL_PROC) & (o.modId # -1) & (OCS.sym # S_LPAREN) &
     ~((o.nparams = 0) & (o.typ # NIL)) THEN
    IF ~ProcSigMatches(pt, o) THEN ErrN("procedure does not match type", o.name) END;
    Emit(OP_PROCVAL);
    EmitU32Raw(mod);
    EmitU32Raw(o.procIndex);
    IF o.level = 0 THEN steps := -1 ELSE steps := curLevel - o.level END;
    EmitU32Raw(steps);
    RETURN TRUE
  END;
  OCS.Restore(ls);
  RETURN FALSE
END TryEmitProcValue;

PROCEDURE ParseArgsList(params: Obj; nm: ARRAY OF CHAR);
VAR p, a: Obj; m2: INTEGER; at: Type;
    ok, more: BOOLEAN;
BEGIN
  Expect(S_LPAREN);
  p := params;
  IF OCS.sym # S_RPAREN THEN
    more := TRUE;
    WHILE more DO
      IF p = NIL THEN ErrN("too many arguments in call to", nm) END;
      IF p.isVarParam THEN
        a := ReadFirstIdent(m2);
        IF a.cls # CL_VAR THEN Err("VAR parameter needs a variable") END;
        IF p.typ.kind = TK_ARRAY THEN
          at := ParseDesignator(M_VARARG, a, m2)
        ELSE
          at := ParseDesignator(M_ADDR, a, m2)
        END;
        ok := TypeEquals(p.typ, at) OR
              ((p.typ.kind = TK_ARRAY) & p.typ.anyCharArray &
               (at.kind = TK_ARRAY) & (at.elem.kind = TK_CHAR)) OR
              ((p.typ.kind = TK_ARRAY) & p.typ.anyCharArray &
               (at.kind = TK_POINTER) & (at.to.kind = TK_ARRAY) & (at.to.elem.kind = TK_CHAR)) OR
              ((p.typ.kind = TK_ARRAY) & p.typ.isOpen &
               (at.kind = TK_ARRAY) & TypeEquals(p.typ.elem, at.elem)) OR
              ((p.typ.kind = TK_ARRAY) & p.typ.isOpen &
               (at.kind = TK_POINTER) & (at.to.kind = TK_ARRAY) & TypeEquals(p.typ.elem, at.to.elem));
        IF ~ok THEN ErrN("VAR argument type mismatch in", nm) END
      ELSIF (p.typ.kind = TK_PROC) & TryEmitProcValue(p.typ) THEN
        (* procedure value passed as actual argument *)
      ELSE
        IF p.typ.kind = TK_RECORD THEN ErrN("record value parameters not supported (use VAR) in", nm) END;
        at := ParseExpression();
        IF ~TypeAssignable(p.typ, at) THEN ErrN("argument type mismatch in", nm) END;
        IF (p.typ = typeReal) & (at = typeInt) THEN Emit(OP_I2F) END
      END;
      p := p.nextParam;
      IF ~Accept(S_COMMA) THEN more := FALSE END
    END
  END;
  Expect(S_RPAREN);
  IF p # NIL THEN ErrN("too few arguments in call to", nm) END
END ParseArgsList;

PROCEDURE ParseCallArgs(proc: Obj; mod: INTEGER);
BEGIN
  ParseArgsList(proc.params, proc.name);
  EmitCall(proc, mod)
END ParseCallArgs;

(* ---------- statements ---------- *)
PROCEDURE PredefinedStatement(o: Obj);
VAR m2, m, ix, delta: INTEGER; a: Obj; t, nt, et: Type;
    n, by: LONGINT; btemp: INTEGER; L, jz, back: INTEGER; vo: Obj;
BEGIN
  CASE o.builtinId OF
    PD_NEW:
      Expect(S_LPAREN);
      a := ReadFirstIdent(m2);
      t := ParseDesignator(M_ADDR, a, m2);
      IF (t.kind # TK_POINTER) OR
         ~((t.to.kind = TK_RECORD) OR ((t.to.kind = TK_ARRAY) & ~t.to.isOpen)) THEN
        Err("NEW requires a pointer to record or to fixed array variable")
      END;
      FindTypeRef(t, m, ix);
      EmitTypeOp(OP_NEW, m, ix);
      Emit(OP_STORE_AT);
      Expect(S_RPAREN)
  | PD_DISPOSE:
      Expect(S_LPAREN);
      a := ReadFirstIdent(m2);
      IF a.cls # CL_VAR THEN Err("DISPOSE needs a pointer variable") END;
      t := ParseDesignator(M_ADDR, a, m2);
      IF t.kind # TK_POINTER THEN Err("DISPOSE requires a pointer variable") END;
      FindTypeRef(t, m, ix);
      EmitTypeOp(OP_DISPOSE, m, ix);
      Expect(S_RPAREN)
  | PD_INC, PD_DEC:
      IF o.builtinId = PD_INC THEN delta := 1 ELSE delta := -1 END;
      Expect(S_LPAREN);
      a := ReadFirstIdent(m2);
      t := ParseDesignator(M_ADDR, a, m2);
      IF t # typeInt THEN Err("INC/DEC require INTEGER variable") END;
      n := delta;
      IF Accept(S_COMMA) THEN
        n := ParseConstExpr(nt);
        IF nt # typeInt THEN Err("INC/DEC amount must be INTEGER constant") END;
        n := delta * n
      END;
      Expect(S_RPAREN);
      Emit(OP_DUP);
      Emit(OP_LOAD_AT);
      Emit32(OP_CONST_I, n);
      Emit(OP_IADD);
      Emit(OP_STORE_AT)
  | PD_INCL, PD_EXCL:
      Expect(S_LPAREN);
      a := ReadFirstIdent(m2);
      t := ParseDesignator(M_ADDR, a, m2);
      IF t # typeSet THEN Err("INCL/EXCL require SET variable") END;
      Emit(OP_DUP);
      Emit(OP_LOAD_AT);
      Expect(S_COMMA);
      et := ParseExpression();
      IF et # typeInt THEN Err("set element must be INTEGER") END;
      Expect(S_RPAREN);
      Emit32(OP_CONST_I, 1);
      Emit(OP_SWAP);
      Emit(OP_SHL);
      IF o.builtinId = PD_INCL THEN Emit(OP_SET_UNION) ELSE Emit(OP_SET_DIFF) END;
      Emit(OP_STORE_AT)
  | PD_COPY:
      Expect(S_LPAREN);
      t := ParseExpression();
      IF (t.kind # TK_ARRAY) OR (t.elem.kind # TK_CHAR) THEN Err("COPY requires char arrays") END;
      Expect(S_COMMA);
      t := ParseExpression();
      IF (t.kind # TK_ARRAY) OR (t.elem.kind # TK_CHAR) THEN Err("COPY requires char arrays") END;
      Expect(S_RPAREN);
      Emit(OP_COPY_STR)
  ELSE ErrN("is not a statement procedure here", o.name)
  END
END PredefinedStatement;

PROCEDURE IsEndSym(): BOOLEAN;
BEGIN
  RETURN (OCS.sym = S_END) OR (OCS.sym = S_ELSE) OR (OCS.sym = S_ELSIF) OR
         (OCS.sym = S_UNTIL) OR (OCS.sym = S_PIPE) OR (OCS.sym = S_EOF)
END IsEndSym;

PROCEDURE ParseStatement();
VAR mod, m2, m, ix: INTEGER;
    o, a, vo, selObj, v: Obj;
    t, lt, rt, at, bt, ct, xt, rec, rt0, saved, pt: Type;
    endJmps: ARRAY 64 OF INTEGER; nEnd, jz, i, L, back: INTEGER;
    btemp: INTEGER; isLong: BOOLEAN; by: LONGINT; vn: ARRAY 64 OF CHAR;
    xtemp, dispatchJmp, defPos, after, elseStart, bodyPos, lastJz, m0, ix0: INTEGER;
    endJmps2: ARRAY 128 OF INTEGER; nEnd2: INTEGER;
    bodyStart: ARRAY 128 OF INTEGER;
    labLo, labHi, labBr: ARRAY 512 OF INTEGER; nLab, nb: INTEGER;
    pendFail: ARRAY 512 OF INTEGER; nPend: INTEGER;
    bodyJmps: ARRAY 16 OF INTEGER; nBody: INTEGER;
    rangeTooBig, useTable, more, more2, ok: BOOLEAN;
    rec2: Type; sh: Obj;
    mn, mx, tsize, ts, defTarget: INTEGER;
    tgt: ARRAY 1024 OF INTEGER;
    tgtPos: ARRAY 1024 OF INTEGER;
    lo, hi: LONGINT; lt2: Type;
    shBase: INTEGER;
    ls: OCS.LexState;
BEGIN
  IF OCS.sym = S_IDENT THEN
    o := ReadFirstIdent(mod);
    IF o.cls = CL_PROC THEN
      IF o.modId = -1 THEN
        IF o.builtinId = PD_HALT THEN
          Expect(S_LPAREN);
          t := ParseExpression();
          IF t # typeInt THEN Err("HALT requires INTEGER") END;
          Expect(S_RPAREN);
          Emit(OP_CALL); EmitU32Raw(255); EmitU32Raw(B_HALT); EmitU32Raw(0)
        ELSE PredefinedStatement(o) END
      ELSE
        IF OCS.sym = S_LPAREN THEN ParseCallArgs(o, mod)
        ELSIF o.nparams = 0 THEN EmitCall(o, mod)
        ELSE ErrN("expected ( in call to", o.name) END
      END;
      RETURN
    END;
    IF (o.cls = CL_VAR) & (o.typ # NIL) & (o.typ.kind = TK_PROC) & (OCS.sym # S_ASSIGN) THEN
      pt := o.typ;
      IF OCS.sym = S_LPAREN THEN
        ParseArgsList(pt.params, o.name);
        dummyT := ParseDesignator(M_VAL, o, mod);
        Emit(OP_CALLP)
      ELSIF pt.nparams = 0 THEN
        dummyT := ParseDesignator(M_VAL, o, mod);
        Emit(OP_CALLP)
      ELSE ErrN("expected ( in call through", o.name) END;
      IF pt.result # NIL THEN Emit(OP_DROP) END;
      RETURN
    END;
    IF o.cls # CL_VAR THEN Err("expected variable, := or call") END;
    (* assignment *)
    lt := ParseDesignator(M_ADDR, o, mod);
    IF OCS.sym # S_ASSIGN THEN Err("expected := or (") END;
    OCS.Next;
    IF lt.kind = TK_ARRAY THEN
      rt := ParseExpression();
      IF ~(TypeEquals(lt, rt) OR (rt.isStringLit & (lt.elem.kind = TK_CHAR))) THEN
        Err("array assignment type mismatch")
      END;
      Emit(OP_TO_ADDR);
      Emit32(OP_CONST_I, rt.ndim + 2);
      Emit(OP_AADD);
      Emit32(OP_COPY, rt.total * TypeElemCells(rt.elem))
    ELSIF lt.kind = TK_RECORD THEN
      rt := ParseExpression();
      IF (rt.kind # TK_RECORD) OR ~TypeEquals(lt, rt) THEN Err("record assignment type mismatch") END;
      Emit32(OP_CONST_I, gDesigHdr);
      Emit(OP_AADD);
      Emit32(OP_COPY, lt.payload)
    ELSIF lt.kind = TK_PROC THEN
      IF ~TryEmitProcValue(lt) THEN
        rt := ParseExpression();
        IF ~TypeAssignable(lt, rt) THEN Err("assignment type mismatch") END
      END;
      Emit(OP_STORE_AT)
    ELSE
      rt := ParseExpression();
      IF ~TypeAssignable(lt, rt) THEN Err("assignment type mismatch") END;
      IF (lt = typeReal) & (rt = typeInt) THEN Emit(OP_I2F) END;
      Emit(OP_STORE_AT)
    END;
    RETURN
  END;
  IF OCS.sym = S_IF THEN
    OCS.Next;
    nEnd := 0;
    jz := 0;
    more := TRUE;
    WHILE more DO
      t := ParseExpression();
      IF t # typeBool THEN Err("IF condition must be BOOLEAN") END;
      jz := EmitJump(OP_JZ);
      Expect(S_THEN);
      ParseStatements();
      IF (OCS.sym = S_ELSIF) OR (OCS.sym = S_ELSE) THEN
        endJmps[nEnd] := EmitJump(OP_JMP); INC(nEnd);
        Patch32(jz, Here());
        jz := -1
      END;
      IF OCS.sym = S_ELSIF THEN OCS.Next
      ELSIF OCS.sym = S_ELSE THEN OCS.Next; ParseStatements(); more := FALSE
      ELSE more := FALSE END
    END;
    IF jz >= 0 THEN Patch32(jz, Here()) END;
    Expect(S_END);
    i := 0;
    WHILE i < nEnd DO Patch32(endJmps[i], Here()); INC(i) END;
    RETURN
  END;
  IF OCS.sym = S_WHILE THEN
    (* Oberon-07 Dijkstra guarded loop: WHILE c1 DO S1 {ELSIF c2 DO S2} END *)
    OCS.Next;
    L := Here();
    more := TRUE;
    WHILE more DO
      t := ParseExpression();
      IF t # typeBool THEN Err("WHILE condition must be BOOLEAN") END;
      jz := EmitJump(OP_JZ);
      Expect(S_DO);
      ParseStatements();
      back := EmitJump(OP_JMP);
      Patch32(back, L);
      Patch32(jz, Here());
      IF OCS.sym = S_ELSIF THEN OCS.Next ELSE more := FALSE END
    END;
    Expect(S_END);
    RETURN
  END;
  IF OCS.sym = S_REPEAT THEN
    OCS.Next;
    L := Here();
    ParseStatements();
    Expect(S_UNTIL);
    t := ParseExpression();
    IF t # typeBool THEN Err("UNTIL condition must be BOOLEAN") END;
    jz := EmitJump(OP_JZ);
    Patch32(jz, L);
    RETURN
  END;
  IF OCS.sym = S_FOR THEN
    OCS.Next;
    ReadIdent(vn);
    vo := Lookup(vn);
    IF (vo = NIL) OR (vo.cls # CL_VAR) OR (~IsIntLike(vo.typ) & (vo.typ # typeChar)) THEN
      Err("FOR control variable must be INTEGER, LONGINT or CHAR variable")
    END;
    isLong := (vo.typ = typeLongint);
    Expect(S_ASSIGN);
    dummyT := ParseDesignator(M_ADDR, vo, 0);
    at := ParseExpression();
    IF ~IsIntLike(at) & (at # typeChar) THEN Err("FOR start must be INTEGER, LONGINT or CHAR") END;
    Emit(OP_STORE_AT);
    Expect(S_TO);
    btemp := AllocTemp();
    bt := ParseExpression();
    IF ~IsIntLike(bt) & (bt # typeChar) THEN Err("FOR end must be INTEGER, LONGINT or CHAR") END;
    Emit32(OP_STORE_LOCAL, btemp);
    by := 1;
    IF Accept(S_BY) THEN
      lo := ParseConstExpr(ct);
      IF ~IsIntLike(ct) OR (lo = 0) THEN Err("FOR BY must be a nonzero INTEGER/LONGINT constant") END;
      by := lo
    END;
    Expect(S_DO);
    L := Here();
    dummyT := ParseDesignator(M_VAL, vo, 0);
    Emit32(OP_LOAD_LOCAL, btemp);
    IF by > 0 THEN
      IF isLong THEN Emit(OP_LLE) ELSE Emit(OP_ILE) END
    ELSE
      IF isLong THEN Emit(OP_LGE) ELSE Emit(OP_IGE) END
    END;
    jz := EmitJump(OP_JZ);
    ParseStatements();
    dummyT := ParseDesignator(M_ADDR, vo, 0);
    Emit(OP_DUP);
    Emit(OP_LOAD_AT);
    IF isLong THEN Emit64(OP_CONST_L, by) ELSE Emit32(OP_CONST_I, by) END;
    IF isLong THEN Emit(OP_LADD) ELSE Emit(OP_IADD) END;
    Emit(OP_STORE_AT);
    back := EmitJump(OP_JMP);
    Patch32(back, L);
    Patch32(jz, Here());
    Expect(S_END);
    RETURN
  END;
  IF OCS.sym = S_CASE THEN
    OCS.Next;
    (* peek: plain variable selector narrowed statically inside type-CASE branches *)
    selObj := NIL;
    OCS.Save(ls);
    a := ReadFirstIdent(m2);
    IF (a # NIL) & (a.cls = CL_VAR) & (OCS.sym = S_OF) THEN selObj := a END;
    OCS.Restore(ls);
    xt := ParseExpression();
    IF (xt.kind = TK_POINTER) & (xt.to # NIL) & (xt.to.kind = TK_RECORD) THEN
      (* type CASE *)
      xtemp := AllocTemp();
      Emit32(OP_STORE_LOCAL, xtemp);
      Expect(S_OF);
      nEnd2 := 0; nPend := 0;
      more := TRUE;
      WHILE more & (OCS.sym # S_ELSE) & (OCS.sym # S_END) DO
        i := 0;
        WHILE i < nPend DO Patch32(pendFail[i], Here()); INC(i) END;
        nPend := 0;
        nBody := 0;
        m0 := 0; ix0 := 0; rt0 := NIL;
        lastJz := -1;
        more2 := TRUE;
        WHILE more2 DO (* type labels of this branch *)
          rt := ParseQualType();
          IF rt.kind = TK_POINTER THEN rec := rt.to ELSE rec := rt END;
          IF rec.kind # TK_RECORD THEN Err("type CASE label must be a record type") END;
          FindTypeRef(rec, m, ix);
          IF rt0 = NIL THEN rt0 := rt; m0 := m; ix0 := ix END;
          Emit32(OP_LOAD_LOCAL, xtemp);
          EmitTypeOp(OP_ISTYPE, m, ix);
          jz := EmitJump(OP_JZ);
          IF nBody >= 16 THEN Err("too many labels in one CASE branch") END;
          bodyJmps[nBody] := EmitJump(OP_JMP); INC(nBody);
          IF lastJz >= 0 THEN Patch32(lastJz, Here()) END;
          lastJz := jz;
          IF ~Accept(S_COMMA) THEN more2 := FALSE END
        END;
        Expect(S_COLON);
        IF nPend >= 512 THEN Err("too many CASE branches") END;
        pendFail[nPend] := lastJz; INC(nPend);
        bodyPos := Here();
        i := 0;
        WHILE i < nBody DO Patch32(bodyJmps[i], bodyPos); INC(i) END;
        Emit32(OP_LOAD_LOCAL, xtemp);
        EmitTypeOp(OP_CHECKTYPE, m0, ix0);
        Emit32(OP_STORE_LOCAL, xtemp);
        saved := NIL;
        IF selObj # NIL THEN saved := selObj.typ; selObj.typ := rt0 END;
        ParseStatements();
        IF selObj # NIL THEN selObj.typ := saved END;
        IF nEnd2 >= 128 THEN Err("too many CASE branches") END;
        endJmps2[nEnd2] := EmitJump(OP_JMP); INC(nEnd2);
        IF ~Accept(S_PIPE) THEN more := FALSE END
      END;
      IF Accept(S_ELSE) THEN
        i := 0;
        WHILE i < nPend DO Patch32(pendFail[i], Here()); INC(i) END;
        nPend := 0;
        ParseStatements();
        endJmps2[nEnd2] := EmitJump(OP_JMP); INC(nEnd2)
      END;
      Expect(S_END);
      after := Here();
      i := 0;
      WHILE i < nPend DO Patch32(pendFail[i], after); INC(i) END;
      i := 0;
      WHILE i < nEnd2 DO Patch32(endJmps2[i], after); INC(i) END;
      RETURN
    END;
    IF (xt # typeInt) & (xt # typeChar) THEN Err("CASE expression must be INTEGER or CHAR") END;
    xtemp := AllocTemp();
    Emit32(OP_STORE_LOCAL, xtemp);
    dispatchJmp := EmitJump(OP_JMP);
    nEnd2 := 0;
    nLab := 0;
    rangeTooBig := FALSE;
    Expect(S_OF);
    nb := 0;
    more := TRUE;
    WHILE more & (OCS.sym # S_ELSE) & (OCS.sym # S_END) DO
      more2 := TRUE;
      WHILE more2 DO (* collect this branch's labels *)
        lo := ParseConstExpr(lt2);
        hi := lo;
        IF Accept(S_DOTDOT) THEN hi := ParseConstExpr(lt2) END;
        IF hi < lo THEN Err("bad case range") END;
        IF nLab >= 512 THEN Err("too many case labels") END;
        labLo[nLab] := SYSTEM.L2I(lo); labHi[nLab] := SYSTEM.L2I(hi); labBr[nLab] := nb; INC(nLab);
        IF hi - lo > 64 THEN rangeTooBig := TRUE END;
        IF ~Accept(S_COMMA) THEN more2 := FALSE END
      END;
      Expect(S_COLON);
      bodyStart[nb] := Here();
      ParseStatements();
      endJmps2[nEnd2] := EmitJump(OP_JMP); INC(nEnd2);
      INC(nb);
      IF nb >= 128 THEN Err("too many case branches") END;
      IF ~Accept(S_PIPE) THEN more := FALSE END
    END;
    elseStart := -1;
    IF Accept(S_ELSE) THEN
      elseStart := Here(); ParseStatements();
      endJmps2[nEnd2] := EmitJump(OP_JMP); INC(nEnd2)
    END;
    Expect(S_END);
    (* dispatch code *)
    Patch32(dispatchJmp, Here());
    useTable := ~rangeTooBig & (nLab >= 8);
    tsize := 0;
    IF useTable THEN
      mn := labLo[0]; mx := labHi[0];
      i := 1;
      WHILE i < nLab DO
        IF labLo[i] < mn THEN mn := labLo[i] END;
        IF labHi[i] > mx THEN mx := labHi[i] END;
        INC(i)
      END;
      tsize := mx - mn + 1;
      IF (tsize > 1024) OR (tsize < 8) THEN useTable := FALSE END
    END;
    Emit32(OP_LOAD_LOCAL, xtemp);
    IF useTable THEN
      Emit(OP_JUMPTABLE);
      EmitU32Raw(tsize);
      EmitU32Raw(mn);
      defPos := Here(); EmitU32Raw(0);
      i := 0;
      WHILE i < tsize DO tgt[i] := -1; INC(i) END;
      i := 0;
      WHILE i < nLab DO
        lo := labLo[i];
        WHILE lo <= labHi[i] DO
          tgt[SYSTEM.L2I(lo - mn)] := bodyStart[labBr[i]];
          lo := lo + 1
        END;
        INC(i)
      END;
      i := 0;
      WHILE i < tsize DO
        tgtPos[i] := Here();
        IF tgt[i] >= 0 THEN EmitU32Raw(tgt[i]) ELSE EmitU32Raw(0) END;
        INC(i)
      END;
      i := 0;
      WHILE i < tsize DO
        IF tgt[i] < 0 THEN tgtPos[i] := -tgtPos[i] - 1 END;
        INC(i)
      END
    ELSE
      i := 0;
      WHILE i < nLab DO
        Emit32(OP_LOAD_LOCAL, xtemp);
        Emit32(OP_CONST_I, labLo[i]);
        Emit(OP_IGE);
        Emit32(OP_LOAD_LOCAL, xtemp);
        Emit32(OP_CONST_I, labHi[i]);
        Emit(OP_ILE);
        Emit(OP_AND);
        jz := EmitJump(OP_JNZ);
        Patch32(jz, bodyStart[labBr[i]]);
        INC(i)
      END;
      defPos := EmitJump(OP_JMP)
    END;
    after := Here();
    i := 0;
    WHILE i < nEnd2 DO Patch32(endJmps2[i], after); INC(i) END;
    IF elseStart >= 0 THEN defTarget := elseStart ELSE defTarget := after END;
    Patch32(defPos, defTarget);
    IF useTable THEN
      ts := tsize;
      i := 0;
      WHILE i < ts DO
        IF tgtPos[i] < 0 THEN Patch32(-tgtPos[i] - 1, defTarget) END;
        INC(i)
      END
    END;
    RETURN
  END;
  IF OCS.sym = S_WITH THEN
    OCS.Next;
    shBase := nWithShadows;
    more := TRUE;
    WHILE more DO
      v := ReadFirstIdent(m2);
      IF (v = NIL) OR (v.cls # CL_VAR) THEN Err("WITH guard needs a pointer variable") END;
      IF (v.typ.kind # TK_POINTER) OR (v.typ.to = NIL) OR (v.typ.to.kind # TK_RECORD) THEN
        Err("WITH guard variable must be a pointer to record")
      END;
      Expect(S_COLON);
      rt := ParseQualType();
      IF rt.kind = TK_POINTER THEN rec := rt.to ELSE rec := rt END;
      IF rec.kind # TK_RECORD THEN Err("WITH guard type must be a record type") END;
      ok := FALSE;
      rec2 := rec;
      WHILE rec2 # NIL DO
        IF rec2 = v.typ.to THEN ok := TRUE END;
        IF rec2.kind = TK_RECORD THEN rec2 := rec2.base ELSE rec2 := NIL END
      END;
      IF ~ok THEN Err("WITH guard type must be the pointee or an extension of it") END;
      dummyT := ParseDesignator(M_VAL, v, m2);
      FindTypeRef(rec, m, ix);
      EmitTypeOp(OP_CHECKTYPE, m, ix);
      Emit(OP_DROP);
      sh := NewObj(v.name, CL_VAR);
      sh.typ := MkPointerType(rec);
      sh.level := v.level;
      sh.offset := v.offset;
      sh.isVarParam := v.isVarParam;
      sh.next := scopeStack[scopeTop];
      scopeStack[scopeTop] := sh;
      IF nWithShadows < 64 THEN withShadows[nWithShadows] := sh; INC(nWithShadows) END;
      IF ~Accept(S_COMMA) THEN more := FALSE END
    END;
    Expect(S_DO);
    ParseStatements();
    Expect(S_END);
    WHILE nWithShadows > shBase DO
      DEC(nWithShadows);
      scopeStack[scopeTop] := withShadows[nWithShadows].next
    END;
    RETURN
  END;
  IF OCS.sym = S_RETURN THEN
    OCS.Next;
    IF curProc.hasResult = 1 THEN
      IF (curProc.result.kind = TK_PROC) & TryEmitProcValue(curProc.result) THEN
        (* RETURN ProcIdent *)
      ELSE
        t := ParseExpression();
        IF ~TypeAssignable(curProc.result, t) THEN Err("RETURN type mismatch") END;
        IF (curProc.result = typeReal) & (t = typeInt) THEN Emit(OP_I2F) END
      END
    ELSIF (OCS.sym # S_SEMI) & ~IsEndSym() THEN
      Err("RETURN takes no expression in a plain procedure")
    END;
    Emit(OP_RET);
    RETURN
  END
  (* empty statement *)
END ParseStatement;

PROCEDURE ParseStatements();
BEGIN
  IF ~IsEndSym() THEN ParseStatement() END;
  WHILE Accept(S_SEMI) DO
    IF IsEndSym() THEN RETURN END;
    ParseStatement()
  END
END ParseStatements;

(* ---------- .obc loader (port of module.c loadModuleFile; types+members only) ---------- *)
PROCEDURE R8(f: Files.File): INTEGER;
BEGIN RETURN Files.ReadByte(f) END R8;

PROCEDURE RU32(f: Files.File): LONGINT;
VAR b0, b1, b2, b3: INTEGER;
BEGIN
  b0 := R8(f); b1 := R8(f); b2 := R8(f); b3 := R8(f);
  RETURN SYSTEM.BOR(SYSTEM.BOR(b0, SYSTEM.LSH(b1, 8)), SYSTEM.BOR(SYSTEM.LSH(b2, 16), SYSTEM.LSH(b3, 24)))
END RU32;

PROCEDURE RU64(f: Files.File): LONGINT;
VAR i: INTEGER; v: LONGINT;
BEGIN
  v := 0;
  i := 0;
  WHILE i < 8 DO v := SYSTEM.BOR(v, SYSTEM.LSH(R8(f), 8*i)); INC(i) END;
  RETURN v
END RU64;

(* read a length-prefixed string into a fresh StrRef *)
PROCEDURE RStr(f: Files.File): StrRef;
VAR n: LONGINT; r: StrRef; i: INTEGER; buf: ARRAY 4096 OF CHAR;
BEGIN
  n := RU32(f);
  IF n > 4095 THEN n := 4095 END;
  IF n > 0 THEN Files.Read(f, buf, SYSTEM.L2I(n)) END;
  NEW(r);
  i := 0;
  WHILE i < n DO r^[i] := buf[i]; INC(i) END;
  r^[i] := 0X;
  RETURN r
END RStr;

PROCEDURE ResolveIdx(raw: LONGINT; lm: LoadedMod): Type;
BEGIN
  IF raw = -1 THEN RETURN NIL END;
  IF (raw >= 0) & (raw < lm.ntypes) THEN RETURN lm.types[SYSTEM.L2I(raw)] END;
  RETURN NIL
END ResolveIdx;

(* load a .obc file: types (cross-refs resolved) + exported members (port of loadModuleFile) *)
(* load a .obc file: types (cross-refs resolved) + exported members (port of loadModuleFile) *)
PROCEDURE LoadObc(path: ARRAY OF CHAR): LoadedMod;
VAR f: Files.File; lm: LoadedMod; magic: ARRAY 4 OF CHAR;
    ni, ng, nt, np, ns, nc, i, j, k, nd, nf, npar: INTEGER;
    v: LONGINT; t: Type; fl, ftail: Field; o, pa, mhead, mtail: Obj;
    gObjs: ARRAY 256 OF Obj; gRaw: ARRAY 256 OF INTEGER;
    pObjs: ARRAY 256 OF Obj; pResultRaw: ARRAY 256 OF INTEGER;
    cObjs: ARRAY 256 OF Obj; cRaw: ARRAY 256 OF INTEGER;
BEGIN
  f := Files.Open(path);
  IF f = NIL THEN ErrN("cannot open", path) END;
  Files.Read(f, magic, 4);
  IF ~NameEqS(magic, "OBC7") THEN ErrN("bad .obc magic", path) END;
  IF RU32(f) # 1 THEN ErrN("bad .obc version", path) END;
  NEW(lm); NEW(lm.name); dummyR := RStr(f); CopyStr(dummyR^, lm.name^);
  NEW(lm.types);
  lm.ntypes := 0; lm.members := NIL; lm.modId := 0;
  ni := SYSTEM.L2I(RU32(f));
  i := 0; WHILE i < ni DO dummyR := RStr(f); INC(i) END;
  RU32(f); (* globalSize *)
  ng := SYSTEM.L2I(RU32(f));
  i := 0;
  WHILE i < ng DO
    dummyR := RStr(f); o := NewObj(dummyR^, CL_VAR);
    o.offset := SYSTEM.L2I(RU32(f));
    gRaw[i] := SYSTEM.L2I(RU32(f));
    IF R8(f) = 1 THEN o.exported := 1 END;
    o.level := 0;
    gObjs[i] := o;
    INC(i)
  END;
  nt := SYSTEM.L2I(RU32(f));
  IF nt > MAXTYPE THEN Err("too many types in import") END;
  lm.ntypes := nt;
  i := 0;
  WHILE i < nt DO
    k := R8(f);
    CASE k OF
      TK_INT: t := typeInt
    | TK_REAL: t := typeReal
    | TK_BOOL: t := typeBool
    | TK_CHAR: t := typeChar
    | TK_SET: t := typeSet
    | TK_NIL: t := typeNil
    | TK_LONGINT: t := typeLongint
    ELSE t := NewType(k)
    END;
    NEW(t.name); dummyR := RStr(f); CopyStr(dummyR^, t.name^);
    IF R8(f) = 1 THEN t.exported := TRUE END;
    lm.types[i] := t;
    CASE k OF
      TK_ARRAY:
        nd := SYSTEM.L2I(RU32(f));
        IF nd < 0 THEN t.isOpen := TRUE; t.ndim := 1; t.dims[0] := 1073741823; t.total := 1073741823
        ELSE
          t.ndim := nd; t.total := 1;
          j := 0;
          WHILE j < nd DO t.dims[j] := SYSTEM.L2I(RU32(f)); t.total := t.total * t.dims[j]; INC(j) END
        END;
        t.raw := SYSTEM.L2I(RU32(f)) (* elem raw *)
    | TK_RECORD:
        t.payload := SYSTEM.L2I(RU32(f));
        t.raw := SYSTEM.L2I(RU32(f)) (* base raw; -1 = none *);
        nf := SYSTEM.L2I(RU32(f));
        ftail := NIL; t.fields := NIL; t.nfields := nf;
        j := 0;
        WHILE j < nf DO
          NEW(fl); NEW(fl.name); dummyR := RStr(f); CopyStr(dummyR^, fl.name^);
          fl.raw := SYSTEM.L2I(RU32(f)); (* type raw *)
          fl.offset := SYSTEM.L2I(RU32(f));
          fl.next := NIL;
          IF t.fields = NIL THEN t.fields := fl ELSE ftail.next := fl END;
          ftail := fl;
          INC(j)
        END
    | TK_POINTER:
        t.raw := SYSTEM.L2I(RU32(f)) (* to raw *)
    | TK_PROC:
        npar := SYSTEM.L2I(RU32(f));
        t.nparams := npar;
        t.params := NIL;
        j := 0;
        WHILE j < npar DO
          NEW(pa); pa.cls := CL_VAR; pa.typ := NIL; pa.nextParam := NIL;
          pa.offset := SYSTEM.L2I(RU32(f)); (* raw type idx *)
          IF R8(f) = 1 THEN pa.isVarParam := TRUE ELSE pa.isVarParam := FALSE END;
          IF t.params = NIL THEN t.params := pa
          ELSE o := t.params; WHILE o.nextParam # NIL DO o := o.nextParam END; o.nextParam := pa END;
          INC(j)
        END;
        t.raw := SYSTEM.L2I(RU32(f)) (* result raw, -1 = none *)
    ELSE
    END;
    INC(i)
  END;
  (* resolve cross refs *)
  i := 0;
  WHILE i < nt DO
    t := lm.types[i];
    CASE t.kind OF
      TK_ARRAY: t.elem := ResolveIdx(t.raw, lm)
    | TK_POINTER: t.to := ResolveIdx(t.raw, lm)
    | TK_RECORD:
        t.base := ResolveIdx(t.raw, lm);
        fl := t.fields;
        WHILE fl # NIL DO fl.typ := ResolveIdx(fl.raw, lm); fl := fl.next END
    | TK_PROC:
        pa := t.params;
        WHILE pa # NIL DO pa.typ := ResolveIdx(pa.offset, lm); pa := pa.nextParam END;
        t.result := ResolveIdx(t.raw, lm)
    ELSE
    END;
    INC(i)
  END;
  i := 0;
  WHILE i < ng DO gObjs[i].typ := ResolveIdx(gRaw[i], lm); INC(i) END;
  (* procs *)
  np := SYSTEM.L2I(RU32(f));
  i := 0;
  WHILE i < np DO
    dummyR := RStr(f); o := NewObj(dummyR^, CL_PROC);
    o.procIndex := i;
    IF R8(f) = 1 THEN o.exported := 1 END;
    R8(f); (* isBody *)
    npar := SYSTEM.L2I(RU32(f));
    o.nparams := npar;
    o.params := NIL;
    j := 0;
    WHILE j < npar DO
      NEW(pa); pa.cls := CL_VAR;
      dummyR := RStr(f); (* param name *)
      pa.offset := SYSTEM.L2I(RU32(f)); (* raw type *)
      IF R8(f) = 1 THEN pa.isVarParam := TRUE ELSE pa.isVarParam := FALSE END;
      pa.nextParam := NIL;
      IF o.params = NIL THEN o.params := pa
      ELSE pa2 := o.params; WHILE pa2.nextParam # NIL DO pa2 := pa2.nextParam END; pa2.nextParam := pa END;
      INC(j)
    END;
    RU32(f); (* nlocals *)
    R8(f); (* hasResult *)
    pResultRaw[i] := SYSTEM.L2I(RU32(f));
    v := RU32(f); (* codelen *)
    j := 0;
    WHILE j < v DO
      k := 4096; IF v - j < 4096 THEN k := SYSTEM.L2I(v - j) END;
      Files.Read(f, scratch, k);
      j := j + k
    END;
    pObjs[i] := o;
    INC(i)
  END;
  i := 0;
  WHILE i < np DO
    pa := pObjs[i].params;
    WHILE pa # NIL DO pa.typ := ResolveIdx(pa.offset, lm); pa := pa.nextParam END;
    pObjs[i].typ := ResolveIdx(pResultRaw[i], lm);
    INC(i)
  END;
  (* strings *)
  ns := SYSTEM.L2I(RU32(f));
  i := 0; WHILE i < ns DO dummyR := RStr(f); INC(i) END;
  (* consts (optional) *)
  nc := 0;
  IF ~Files.Eof(f) THEN
    nc := SYSTEM.L2I(RU32(f));
    i := 0;
    WHILE i < nc DO
      dummyR := RStr(f); o := NewObj(dummyR^, CL_CONST);
      cRaw[i] := SYSTEM.L2I(RU32(f));
      o.cval := RU64(f);
      IF R8(f) = 1 THEN o.exported := 1 END;
      cObjs[i] := o;
      INC(i)
    END;
    i := 0;
    WHILE i < nc DO cObjs[i].typ := ResolveIdx(cRaw[i], lm); INC(i) END
  END;
  Files.Close(f);
  (* members: exported procs, named non-basic types, exported vars, exported consts *)
  mhead := NIL; mtail := NIL;
  i := 0;
  WHILE i < np DO
    IF pObjs[i].exported = 1 THEN AppendMember(mhead, mtail, pObjs[i]) END;
    INC(i)
  END;
  i := 0;
  WHILE i < nt DO
    t := lm.types[i];
    IF (t.kind # TK_INT) & (t.kind # TK_REAL) & (t.kind # TK_BOOL) & (t.kind # TK_CHAR) &
       (t.kind # TK_SET) & (t.kind # TK_NIL) & (t.kind # TK_UNDEF) & (t.name^[0] # 0X) THEN
      o := NewObj(t.name^, CL_TYPE);
      o.typ := t;
      AppendMember(mhead, mtail, o)
    END;
    INC(i)
  END;
  i := 0;
  WHILE i < ng DO
    IF gObjs[i].exported = 1 THEN AppendMember(mhead, mtail, gObjs[i]) END;
    INC(i)
  END;
  i := 0;
  WHILE i < nc DO
    IF cObjs[i].exported = 1 THEN AppendMember(mhead, mtail, cObjs[i]) END;
    INC(i)
  END;
  lm.members := mhead;
  RETURN lm
END LoadObc;

(* ---------- module search path (port of module.c obSearchDirs, OBERON_HOME/OBERON_PATH) ---------- *)
PROCEDURE EndsWithBin(VAR s: ARRAY OF CHAR): BOOLEAN;
VAR n: INTEGER;
BEGIN
  n := StrLenA(s);
  RETURN (n >= 4) & (s[n-4] = '/') & (CAP(s[n-3]) = 'B') & (CAP(s[n-2]) = 'I') & (CAP(s[n-1]) = 'N')
END EndsWithBin;

PROCEDURE OberonHome();
VAR n, i, k: INTEGER; ok: BOOLEAN;
BEGIN
  ok := SYSTEM.GETENV("OBERON_HOME", home);
  IF ok & (home[0] # 0X) THEN RETURN END;
  n := SYSTEM.EXEPATH(ex);
  i := n;
  WHILE (i > 0) & (ex[i-1] # '/') & (ex[i-1] # '\') DO DEC(i) END;
  IF i = 0 THEN home[0] := '.'; home[1] := 0X
  ELSE
    k := 0;
    WHILE k < i DO home[k] := ex[k]; INC(k) END;
    home[k] := 0X;
    IF EndsWithBin(home) THEN home[k-4] := 0X END
  END
END OberonHome;

(* try to find <dir>/<nm>.obc in the search path; returns TRUE and fills path *)
PROCEDURE FindObc(nm, path: ARRAY OF CHAR): BOOLEAN;
VAR dirs: ARRAY 80 OF DirRef; nd, i, j: INTEGER;
    sep: CHAR; haveLib, ok, more: BOOLEAN; libd: ARRAY 600 OF CHAR; d2: ARRAY 600 OF CHAR;
    tok: ARRAY 600 OF CHAR;
BEGIN
  nd := 0;
  NEW(dirs[nd]); CopyStr(inDir, dirs[nd]); INC(nd);
  CopyStr(inDir, d2); AppendStr(d2, "/../lib"); NEW(dirs[nd]); CopyStr(d2, dirs[nd]); INC(nd);
  CopyStr(inDir, d2); AppendStr(d2, "/../../lib"); NEW(dirs[nd]); CopyStr(d2, dirs[nd]); INC(nd);
  CopyStr(inDir, d2); AppendStr(d2, "/../../selfhost"); NEW(dirs[nd]); CopyStr(d2, dirs[nd]); INC(nd);
  NEW(dirs[nd]); CopyStr(".", dirs[nd]); INC(nd); (* "." en tete de OBERON_PATH *)
  OberonHome();
  CopyStr(home, libd); AppendStr(libd, "/lib");
  haveLib := FALSE;
  ok := SYSTEM.GETENV("OBERON_PATH", pth);
  IF ok THEN
    sep := ':';
    i := 0;
    WHILE ex[i] # 0X DO IF ex[i] = '\' THEN sep := ';' END; INC(i) END;
    i := 0; j := 0; more := TRUE;
    WHILE more DO
      IF (pth[i] = sep) OR (pth[i] = 0X) THEN
        tok[j] := 0X;
        IF j > 0 THEN
          IF nd < 80 THEN NEW(dirs[nd]); CopyStr(tok, dirs[nd]); INC(nd) END;
          IF NameEqS(tok, libd) THEN haveLib := TRUE END
        END;
        IF pth[i] = 0X THEN more := FALSE ELSE INC(i); j := 0 END
      ELSE
        tok[j] := pth[i]; INC(j); INC(i)
      END
    END
  END;
  IF ~haveLib THEN
    IF nd < 80 THEN NEW(dirs[nd]); CopyStr(libd, dirs[nd]); INC(nd) END
  END;
  i := 0;
  WHILE i < nd DO
    CopyStr(dirs[i], path);
    AppendStr(path, "/");
    AppendStr(path, nm);
    AppendStr(path, ".obc");
    IF Files.Exists(path) THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END FindObc;

(* ---------- imports ---------- *)
PROCEDURE InstallImport(real, alias: ARRAY OF CHAR);
VAR cp, src, mo, m: Obj; isBuiltin: BOOLEAN; lm: LoadedMod; modId, i, j: INTEGER;
    path: ARRAY 600 OF CHAR;
BEGIN
  isBuiltin := TRUE;
  IF NameEqS(real, "Out") THEN src := builtinOut
  ELSIF NameEqS(real, "In") THEN src := builtinIn
  ELSIF NameEqS(real, "Files") THEN src := builtinFiles
  ELSIF NameEqS(real, "SYSTEM") THEN src := builtinSystem
  ELSE isBuiltin := FALSE; src := NIL END;
  IF isBuiltin THEN
    cp := NewObj(alias, CL_MODULE);
    cp.modId := 255; cp.builtin := TRUE; cp.members := src.members;
    InsertObj(cp)
  ELSE
    (* real module: find + load its .obc (cached) *)
    lm := NIL;
    i := 0;
    WHILE i < nImpCache DO
      IF NameEqS(impCache[i].name^, real) THEN lm := impCache[i] END;
      INC(i)
    END;
    IF lm = NIL THEN
      IF ~FindObc(real, path) THEN ErrN("cannot find module", real) END;
      lm := LoadObc(path);
      IF nImpCache < MAXIMP THEN
        impCache[nImpCache] := lm;
        NEW(impNames[nimports]); CopyStr(real, impNames[nimports]);
        INC(nImpCache); INC(nimports);
        lm.modId := nimports
      END
    END;
    modId := lm.modId;
    mo := NewObj(alias, CL_MODULE);
    mo.modId := modId; mo.builtin := FALSE; mo.members := lm.members;
    (* set defMod/defTypeIdx on type members, modId on var members *)
    m := mo.members;
    WHILE m # NIL DO
      IF m.cls = CL_TYPE THEN
        m.defMod := modId;
        j := 0;
        WHILE j < lm.ntypes DO
          IF lm.types[j] = m.typ THEN m.defTypeIdx := j END;
          INC(j)
        END
      END;
      IF m.cls = CL_VAR THEN m.modId := modId END;
      m := m.next
    END;
    InsertObj(mo)
  END
END InstallImport;

(* @@NEXT@@ *)

(* ---------- .obc writer (must match bootstrap/src/module.c writeModule byte for byte) ---------- *)
PROCEDURE W8(v: LONGINT);
BEGIN Files.WriteByte(outF, SYSTEM.L2I(SYSTEM.BAND(v, 255))) END W8;

PROCEDURE W32(v: LONGINT);
BEGIN
  W8(SYSTEM.BAND(v, 255));
  W8(SYSTEM.BAND(SYSTEM.LSH(v, -8), 255));
  W8(SYSTEM.BAND(SYSTEM.LSH(v, -16), 255));
  W8(SYSTEM.BAND(SYSTEM.LSH(v, -24), 255))
END W32;

PROCEDURE W64(v: LONGINT);
VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE i < 8 DO W8(SYSTEM.BAND(SYSTEM.LSH(v, -8*i), 255)); INC(i) END
END W64;

PROCEDURE WStr(s: ARRAY OF CHAR);
VAR n: INTEGER;
BEGIN
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  W32(n);
  Files.Write(outF, s, n)
END WStr;

PROCEDURE WStrR(r: StrRef);
BEGIN WStr(r^) END WStrR;

PROCEDURE WriteType(t: Type);
VAR fl: Field; pa: Obj; i: INTEGER;
BEGIN
  W8(t.kind);
  WStrR(t.name);
  IF t.exported THEN W8(1) ELSE W8(0) END;
  CASE t.kind OF
    TK_ARRAY:
      IF t.isOpen THEN W32(-1)
      ELSE
        W32(t.ndim);
        i := 0;
        WHILE i < t.ndim DO W32(t.dims[i]); INC(i) END
      END;
      W32(TypeIndex(t.elem))
  | TK_RECORD:
      W32(t.payload);
      IF t.base # NIL THEN W32(TypeIndex(t.base)) ELSE W32(-1) END;
      W32(t.nfields);
      fl := t.fields;
      WHILE fl # NIL DO
        WStrR(fl.name);
        W32(TypeIndex(fl.typ));
        W32(fl.offset);
        fl := fl.next
      END
  | TK_POINTER:
      W32(TypeIndex(t.to))
  | TK_PROC:
      W32(t.nparams);
      pa := t.params;
      WHILE pa # NIL DO
        W32(TypeIndex(pa.typ));
        IF pa.isVarParam THEN W8(1) ELSE W8(0) END;
        pa := pa.nextParam
      END;
      IF t.result # NIL THEN W32(TypeIndex(t.result)) ELSE W32(-1) END
  ELSE
  END
END WriteType;

PROCEDURE WriteModule();
VAR o: Obj; p: Proc; pa: Obj; cb: CodeBlock; i, j: INTEGER; ng, nc: INTEGER;
BEGIN
  (* register every reachable type first (fresh stamp, like stage-0 gTypeStamp++) *)
  INC(gStamp);
  o := globalsList;
  WHILE o # NIL DO RegisterTypeDeep(o.typ); o := o.nextGlobal END;
  i := 0;
  WHILE i < nprocs DO
    p := procs[i];
    pa := p.params;
    WHILE pa # NIL DO RegisterTypeDeep(pa.typ); pa := pa.nextParam END;
    RegisterTypeDeep(p.result);
    INC(i)
  END;
  Files.Write(outF, "OBC7", 4);
  W32(1);
  WStr(modName);
  W32(nimports);
  i := 0;
  WHILE i < nimports DO WStrR(impNames[i]); INC(i) END;
  W32(globalSize);
  ng := 0;
  o := globalsList;
  WHILE o # NIL DO INC(ng); o := o.nextGlobal END;
  W32(ng);
  o := globalsList;
  WHILE o # NIL DO
    WStrR(o.name);
    W32(o.offset);
    W32(TypeIndex(o.typ));
    IF o.exported = 1 THEN W8(1) ELSE W8(0) END;
    o := o.nextGlobal
  END;
  W32(ntypes);
  i := 0;
  WHILE i < ntypes DO WriteType(types[i]); INC(i) END;
  W32(nprocs);
  i := 0;
  WHILE i < nprocs DO
    p := procs[i];
    WStrR(p.name);
    IF p.exported THEN W8(1) ELSE W8(0) END;
    IF p.isBody THEN W8(1) ELSE W8(0) END;
    W32(p.nparams);
    pa := p.params;
    WHILE pa # NIL DO
      WStrR(pa.name);
      W32(TypeIndex(pa.typ));
      IF pa.isVarParam THEN W8(1) ELSE W8(0) END;
      pa := pa.nextParam
    END;
    W32(p.nlocals);
    W8(p.hasResult);
    IF p.hasResult = 1 THEN W32(TypeIndex(p.result)) ELSE W32(-1) END;
    W32(p.codeLen);
    cb := p.codeHead;
    WHILE cb # NIL DO
      j := 0;
      WHILE j < cb.len DO Files.WriteByte(outF, ORD(cb.data[j])); INC(j) END;
      cb := cb.next
    END;
    INC(i)
  END;
  W32(nstrings);
  i := 0;
  WHILE i < nstrings DO WStrR(strs[i]); INC(i) END;
  nc := 0;
  o := constsList;
  WHILE o # NIL DO INC(nc); o := o.nextConst END;
  W32(nc);
  o := constsList;
  WHILE o # NIL DO
    WStrR(o.name);
    W32(TypeIndex(o.typ));
    W64(o.cval);
    IF o.exported = 1 THEN W8(1) ELSE W8(0) END;
    o := o.nextConst
  END
END WriteModule;

(* ---------- main ---------- *)
PROCEDURE StrLenA(s: ARRAY OF CHAR): INTEGER;
VAR n: INTEGER;
BEGIN n := 0; WHILE s[n] # 0X DO INC(n) END; RETURN n END StrLenA;

PROCEDURE AppendStr(VAR dst: ARRAY OF CHAR; suf: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN
  i := StrLenA(dst); j := 0;
  WHILE (suf[j] # 0X) & (i < LEN(dst, 0) - 1) DO dst[i] := suf[j]; INC(i); INC(j) END;
  dst[i] := 0X
END AppendStr;

VAR bodyIdx, i, dot: INTEGER;
    a1: ARRAY 600 OF CHAR;
    haveOut: BOOLEAN;
BEGIN
  IF SYSTEM.ARGC < 1 THEN
    Out.String("usage: OC <file.Mod> [-o <file.obc>]"); Out.Ln; SYSTEM.EXIT(2)
  END;
  SYSTEM.ARGV(0, inPath);
  haveOut := FALSE;
  IF SYSTEM.ARGC >= 3 THEN
    SYSTEM.ARGV(1, a1);
    IF NameEqS(a1, "-o") THEN
      SYSTEM.ARGV(2, outPath);
      haveOut := TRUE
    END
  END;
  IF ~haveOut THEN
    CopyStr(inPath, outPath);
    (* replace extension with .obc *)
    dot := StrLenA(outPath) - 1;
    WHILE (dot >= 0) & (outPath[dot] # '.') & (outPath[dot] # '/') & (outPath[dot] # '\') DO DEC(dot) END;
    IF (dot >= 0) & (outPath[dot] = '.') THEN outPath[dot] := 0X END;
    AppendStr(outPath, ".obc")
  END;
  (* dir of input *)
  CopyStr(".", inDir);
  dot := StrLenA(inPath) - 1;
  WHILE (dot >= 0) & (inPath[dot] # '/') & (inPath[dot] # '\') DO DEC(dot) END;
  IF dot > 0 THEN
    i := 0;
    WHILE i < dot DO inDir[i] := inPath[i]; INC(i) END;
    inDir[i] := 0X
  END;

  InitBasicTypes();
  NEW(types); NEW(procs); NEW(strs);
  ntypes := 0; nprocs := 0; nstrings := 0; gStamp := 1;
  globalsList := NIL; constsList := NIL; globalSize := 0;
  nimports := 0; tagCounter := 0;
  scopeTop := -1; nWithShadows := 0; curLevel := 0;
  allowOpenArray := FALSE;
  curProc := NIL;

  OCS.Open(inPath);
  ScopePush();
  InstallPredefined();
  ScopePush();
  MakeBuiltinModules();
  curLevel := 0;
  (* OCS.Open a deja lu le premier token *)
  Expect(S_MODULE);
  ReadIdent(modName);
  Expect(S_SEMI);
  IF OCS.sym = S_IMPORT THEN OCS.Next; ParseImports() END;
  bodyIdx := nprocs;
  dummyP := AddProc("<body>", 0, 1);
  ParseDeclarations(1);
  curProc := procs[bodyIdx];
  curLevel := 0;
  ScopePush();
  IF Accept(S_BEGIN) THEN ParseStatements() END;
  Emit(OP_RET);
  Expect(S_END);
  IF OCS.sym = S_IDENT THEN
    IF ~NameEqS(OCS.name, modName) THEN Err("module name mismatch at END") END;
    OCS.Next
  END;
  Expect(S_DOT);

  outF := Files.Create(outPath);
  IF outF = NIL THEN Out.String("OC: cannot write "); Out.String(outPath); Out.Ln; SYSTEM.EXIT(1) END;
  WriteModule();
  Files.Close(outF);
  Out.String(inPath); Out.String(" -> "); Out.String(outPath);
  Out.String(" ("); Out.Int(nprocs, 0); Out.String(" procs, ");
  Out.Int(ntypes, 0); Out.String(" types, ");
  Out.Int(globalSize, 0); Out.String(" globals, ");
  Out.Int(nstrings, 0); Out.String(" strings)"); Out.Ln
END OC.
