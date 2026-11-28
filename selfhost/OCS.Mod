MODULE OCS;
(* Scanner Oberon-07 — port de bootstrap/src/lexer.c.
   Constantes S_* identiques à l'enum C (lexer.h).  Lecture octet par octet via
   Files + pushback 1 caractere maison.  Pushback de tokens (hist 8 + pb 8)
   pour le parsing spéculatif, comme lexSave/lexRestore en C. *)

IMPORT Out, Files, SYSTEM;

CONST
  S_EOF* = 0; S_IDENT* = 1; S_INT* = 2; S_REAL* = 3; S_CHAR* = 4; S_STRING* = 5;
  S_ARRAY* = 6; S_BEGIN* = 7; S_BY* = 8; S_CASE* = 9; S_CONST* = 10; S_DIV* = 11;
  S_DO* = 12; S_ELSE* = 13; S_ELSIF* = 14; S_END* = 15; S_FOR* = 16; S_HALT* = 17;
  S_IF* = 18; S_IMPORT* = 19; S_IN* = 20; S_IS* = 21; S_MOD* = 22; S_MODULE* = 23;
  S_NIL* = 24; S_OF* = 25; S_OR* = 26; S_POINTER* = 27; S_PROCEDURE* = 28;
  S_RECORD* = 29; S_REPEAT* = 30; S_RETURN* = 31; S_THEN* = 32; S_TO* = 33;
  S_TYPE* = 34; S_UNTIL* = 35; S_VAR* = 36; S_WHILE* = 37; S_WITH* = 38;
  S_ASSIGN* = 39; S_PLUS* = 40; S_MINUS* = 41; S_STAR* = 42; S_SLASH* = 43;
  S_AMP* = 44; S_TILDE* = 45; S_PIPE* = 46; S_EQ* = 47; S_NEQ* = 48; S_LT* = 49;
  S_LE* = 50; S_GT* = 51; S_GE* = 52; S_DOT* = 53; S_DOTDOT* = 54; S_COMMA* = 55;
  S_COLON* = 56; S_SEMI* = 57; S_LPAREN* = 58; S_RPAREN* = 59; S_LBRACK* = 60;
  S_RBRACK* = 61; S_CARET* = 62; S_LBRACE* = 63; S_RBRACE* = 64;

TYPE
  Token = RECORD
    sym, line: INTEGER; ival: LONGINT; rval: REAL; cval: INTEGER;
    name: ARRAY 64 OF CHAR; sval: ARRAY 4096 OF CHAR; slen: INTEGER
  END;
  LexState = RECORD tok: Token; histMark: LONGINT END;

VAR
  sym*: INTEGER;               (* symbole courant *)
  line*: INTEGER;
  ival*: LONGINT;              (* S_INT *)
  rval*: REAL;                 (* S_REAL *)
  cval*: INTEGER;              (* S_CHAR *)
  name*: ARRAY 64 OF CHAR;     (* S_IDENT *)
  sval*: ARRAY 4096 OF CHAR;   (* S_STRING *)
  slen*: INTEGER;
  f: Files.File;
  ch: INTEGER;                 (* lookahead, -1 = EOF *)
  pushed: INTEGER; hasPushed: BOOLEAN;   (* pushback 1 caractere *)
  hist: ARRAY 8 OF Token; histCount: INTEGER;
  pb: ARRAY 8 OF Token; pbN: INTEGER;

PROCEDURE Error(msg: ARRAY OF CHAR);
BEGIN
  Out.String("OCS error line "); Out.Int(line, 0); Out.String(": "); Out.String(msg); Out.Ln;
  HALT(1)
END Error;

PROCEDURE Adv;
BEGIN
  IF hasPushed THEN ch := pushed; hasPushed := FALSE
  ELSE ch := Files.ReadByte(f)   (* -1 at EOF *)
  END;
  IF ch = 10 (* \n *) THEN INC(line) END
END Adv;

PROCEDURE UnGet(c: INTEGER);
BEGIN pushed := c; hasPushed := TRUE END UnGet;

PROCEDURE IsLetter(c: INTEGER): BOOLEAN;
BEGIN RETURN ((c >= 97) & (c <= 122)) OR ((c >= 65) & (c <= 90)) OR (c = 95) END IsLetter;

PROCEDURE IsDigit(c: INTEGER): BOOLEAN;
BEGIN RETURN (c >= 48) & (c <= 57) END IsDigit;

PROCEDURE IsHexLetter(c: INTEGER): BOOLEAN;
BEGIN RETURN ((c >= 65) & (c <= 70)) OR ((c >= 97) & (c <= 102)) END IsHexLetter;

PROCEDURE CopyStr(src, dst: ARRAY OF CHAR; max: INTEGER);
VAR i: INTEGER;
BEGIN i := 0; WHILE (src[i] # 0X) & (i < max-1) DO dst[i] := src[i]; INC(i) END; dst[i] := 0X
END CopyStr;

PROCEDURE Eq(VAR a: ARRAY OF CHAR; b: ARRAY OF CHAR): BOOLEAN;
VAR i: INTEGER;
BEGIN i := 0; WHILE (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END; RETURN (a[i] = 0X) & (b[i] = 0X) END Eq;

(* ---------- conversions ---------- *)

PROCEDURE DigitVal(c: INTEGER): INTEGER;  (* 0-9 A-F a-f -> 0..15, sinon -1 *)
VAR v: INTEGER;
BEGIN
  IF IsDigit(c) THEN RETURN c - 48 END;
  v := c - 65; IF (v >= 0) & (v <= 5) THEN RETURN v + 10 END;
  v := c - 97; IF (v >= 0) & (v <= 5) THEN RETURN v + 10 END;
  RETURN -1
END DigitVal;

PROCEDURE ParseInt(VAR s: ARRAY OF CHAR; base: INTEGER; VAR v: LONGINT);
VAR i, d: INTEGER;
BEGIN
  v := 0; i := 0;
  WHILE s[i] # 0X DO
    d := DigitVal(ORD(s[i]));
    IF (d < 0) OR (d >= base) THEN Error("bad number") END;
    v := v * base + d;
    INC(i)
  END
END ParseInt;

(* v := valeur reelle de s : [chiffres][.chiffres][E[+-]chiffres] *)
PROCEDURE ParseReal(VAR s: ARRAY OF CHAR; VAR v: REAL);
VAR i, d, exp, esign, frac: INTEGER; mant: REAL; seenDot: BOOLEAN;
BEGIN
  mant := 0.0; frac := 0; exp := 0; esign := 1; i := 0; seenDot := FALSE;
  WHILE (s[i] # 0X) & (s[i] # 'E') & (s[i] # 'e') DO
    IF s[i] = '.' THEN seenDot := TRUE
    ELSE
      d := DigitVal(ORD(s[i]));
      IF d >= 0 THEN
        mant := mant * 10.0 + d;
        IF seenDot THEN INC(frac) END
      END
    END;
    INC(i)
  END;
  IF (s[i] = 'E') OR (s[i] = 'e') THEN
    INC(i);
    IF s[i] = '+' THEN esign := 1; INC(i)
    ELSIF s[i] = '-' THEN esign := -1; INC(i)
    END;
    WHILE s[i] # 0X DO
      d := DigitVal(ORD(s[i]));
      IF d >= 0 THEN exp := exp * 10 + d END;
      INC(i)
    END
  END;
  exp := exp * esign - frac;
  WHILE exp > 0 DO mant := mant * 10.0; DEC(exp) END;
  WHILE exp < 0 DO mant := mant / 10.0; INC(exp) END;
  v := mant
END ParseReal;

(* ---------- keywords (casse exacte, majuscules) ---------- *)

PROCEDURE KwLookup(VAR s: ARRAY OF CHAR): INTEGER;
BEGIN
  IF Eq(s, "ARRAY") THEN RETURN S_ARRAY
  ELSIF Eq(s, "BEGIN") THEN RETURN S_BEGIN
  ELSIF Eq(s, "BY") THEN RETURN S_BY
  ELSIF Eq(s, "CASE") THEN RETURN S_CASE
  ELSIF Eq(s, "CONST") THEN RETURN S_CONST
  ELSIF Eq(s, "DIV") THEN RETURN S_DIV
  ELSIF Eq(s, "DO") THEN RETURN S_DO
  ELSIF Eq(s, "ELSE") THEN RETURN S_ELSE
  ELSIF Eq(s, "ELSIF") THEN RETURN S_ELSIF
  ELSIF Eq(s, "END") THEN RETURN S_END
  ELSIF Eq(s, "FOR") THEN RETURN S_FOR
  ELSIF Eq(s, "HALT") THEN RETURN S_HALT
  ELSIF Eq(s, "IF") THEN RETURN S_IF
  ELSIF Eq(s, "IMPORT") THEN RETURN S_IMPORT
  ELSIF Eq(s, "IN") THEN RETURN S_IN
  ELSIF Eq(s, "IS") THEN RETURN S_IS
  ELSIF Eq(s, "MOD") THEN RETURN S_MOD
  ELSIF Eq(s, "MODULE") THEN RETURN S_MODULE
  ELSIF Eq(s, "NIL") THEN RETURN S_NIL
  ELSIF Eq(s, "OF") THEN RETURN S_OF
  ELSIF Eq(s, "OR") THEN RETURN S_OR
  ELSIF Eq(s, "POINTER") THEN RETURN S_POINTER
  ELSIF Eq(s, "PROCEDURE") THEN RETURN S_PROCEDURE
  ELSIF Eq(s, "RECORD") THEN RETURN S_RECORD
  ELSIF Eq(s, "REPEAT") THEN RETURN S_REPEAT
  ELSIF Eq(s, "RETURN") THEN RETURN S_RETURN
  ELSIF Eq(s, "THEN") THEN RETURN S_THEN
  ELSIF Eq(s, "TO") THEN RETURN S_TO
  ELSIF Eq(s, "TYPE") THEN RETURN S_TYPE
  ELSIF Eq(s, "UNTIL") THEN RETURN S_UNTIL
  ELSIF Eq(s, "VAR") THEN RETURN S_VAR
  ELSIF Eq(s, "WHILE") THEN RETURN S_WHILE
  ELSIF Eq(s, "WITH") THEN RETURN S_WITH
  END;
  RETURN S_IDENT
END KwLookup;

(* ---------- token record / pushback ---------- *)

PROCEDURE RecordTok(VAR t: Token);
VAR i: INTEGER;
BEGIN
  t.sym := sym; t.line := line; t.ival := ival; t.rval := rval; t.cval := cval; t.slen := slen;
  (* copie manuelle : t.name/t.sval sont des champs inline d'un record VAR,
     on ne peut pas les passer en param open-array *)
  i := 0; WHILE (name[i] # 0X) & (i < 63) DO t.name[i] := name[i]; INC(i) END; t.name[i] := 0X;
  i := 0; WHILE (sval[i] # 0X) & (i < 4095) DO t.sval[i] := sval[i]; INC(i) END; t.sval[i] := 0X
END RecordTok;

PROCEDURE ApplyTok(VAR t: Token);
VAR i: INTEGER;
BEGIN
  sym := t.sym; line := t.line; ival := t.ival; rval := t.rval; cval := t.cval; slen := t.slen;
  i := 0; WHILE (t.name[i] # 0X) & (i < 63) DO name[i] := t.name[i]; INC(i) END; name[i] := 0X;
  i := 0; WHILE (t.sval[i] # 0X) & (i < 4095) DO sval[i] := t.sval[i]; INC(i) END; sval[i] := 0X
END ApplyTok;

PROCEDURE Save*(VAR st: LexState);
BEGIN RecordTok(st.tok); st.histMark := histCount END Save;

PROCEDURE Restore*(VAR st: LexState);
VAR i: LONGINT;
BEGIN
  ApplyTok(st.tok);
  pbN := 0;
  i := histCount - 1;
  WHILE i >= st.histMark DO
    IF pbN < 8 THEN pb[pbN] := hist[SYSTEM.L2I(i MOD 8)]; INC(pbN) END;
    i := i - 1

  END
END Restore;

(* ---------- scanners ---------- *)

PROCEDURE SkipComment;  (* ch = '(' et suivant '*' ; commentaires imbriqués *)
VAR depth, c2: INTEGER;
BEGIN
  depth := 1; Adv; Adv;
  WHILE depth > 0 DO
    IF ch = -1 THEN Error("unterminated comment") END;
    IF ch = 40 (* '(' *) THEN
      c2 := Files.ReadByte(f);
      IF c2 = 42 (* '*' *) THEN INC(depth); Adv ELSE UnGet(c2); Adv END
    ELSIF ch = 42 (* '*' *) THEN
      c2 := Files.ReadByte(f);
      IF c2 = 41 (* ')' *) THEN DEC(depth); Adv ELSE UnGet(c2); Adv END
    ELSE Adv END
  END
END SkipComment;

PROCEDURE ReadNumber;
VAR buf: ARRAY 128 OF CHAR; n, c2: INTEGER;
    isReal, isHex, isChar, done: BOOLEAN;
BEGIN
  n := 0; isReal := FALSE; isHex := FALSE; isChar := FALSE; done := FALSE;
  WHILE ~done & (IsDigit(ch) OR IsHexLetter(ch) OR (ch = 46 (* '.' *))) DO
    IF ch = 46 (* '.' *) THEN
      c2 := Files.ReadByte(f);
      IF c2 = 46 THEN UnGet(c2); done := TRUE          (* ".." : stop, '.' non consommé *)
      ELSE
        UnGet(c2);
        IF isHex THEN done := TRUE                       (* hex : pas de point *)
        ELSE isReal := TRUE; IF n < 127 THEN buf[n] := '.'; INC(n) END; Adv END
      END
    ELSIF (ch = 101) OR (ch = 69) THEN                   (* e ou E : exposant ou hexa *)
      c2 := Files.ReadByte(f);
      IF (IsDigit(c2) OR (c2 = 43) OR (c2 = 45)) & ~isHex THEN
        isReal := TRUE; IF n < 127 THEN buf[n] := 'E'; INC(n) END; Adv;
        IF (ch = 43) OR (ch = 45) THEN IF n < 127 THEN buf[n] := CHR(ch); INC(n) END; Adv END
      ELSE
        UnGet(c2);
        isHex := TRUE; IF n < 127 THEN buf[n] := 'E'; INC(n) END; Adv
      END
    ELSIF IsHexLetter(ch) THEN                           (* a..f (sauf e) ou A..F *)
      isHex := TRUE;
      IF n < 127 THEN
        IF ch >= 97 THEN buf[n] := CHR(ch - 32) ELSE buf[n] := CHR(ch) END;  (* majuscule *)
        INC(n)
      END;
      Adv
    ELSE                                                 (* chiffre *)
      IF n < 127 THEN buf[n] := CHR(ch); INC(n) END;
      Adv
    END
  END;
  (* suffixes *)
  IF ch = 72 (* H *) THEN isHex := TRUE; Adv
  ELSIF ch = 88 (* X *) THEN isChar := TRUE; isHex := TRUE; Adv
  ELSIF (ch >= 97) & (ch <= 122) THEN
    IF ch = 104 (* h *) THEN isHex := TRUE; Adv
    ELSIF ch = 120 (* x *) THEN isChar := TRUE; isHex := TRUE; Adv
    END
  END;
  buf[n] := 0X;
  IF isChar THEN sym := S_CHAR; ParseInt(buf, 16, ival); cval := SYSTEM.L2I(ival)
  ELSIF isReal THEN sym := S_REAL; ParseReal(buf, rval)
  ELSIF isHex THEN sym := S_INT; ParseInt(buf, 16, ival)
  ELSE sym := S_INT; ParseInt(buf, 10, ival)
  END
END ReadNumber;

PROCEDURE ReadIdent;
VAR n: INTEGER;
BEGIN
  n := 0;
  WHILE IsLetter(ch) OR IsDigit(ch) DO
    IF n < 63 THEN name[n] := CHR(ch); INC(n) END;
    Adv
  END;
  name[n] := 0X;
  sym := KwLookup(name)
END ReadIdent;

PROCEDURE ReadString;
VAR c2: INTEGER;
BEGIN
  Adv; (* ouvrante *)
  slen := 0;
  WHILE TRUE DO
    IF (ch = -1) OR (ch = 10) THEN Error("unterminated string") END;
    IF ch = 34 (* " *) THEN
      c2 := Files.ReadByte(f);
      IF c2 = 34 THEN (* "" = guillemet littéral *)
        IF slen < 4095 THEN sval[slen] := '"'; INC(slen) END;
        Adv; Adv
      ELSE
        UnGet(c2); Adv;   (* fermante *)
        sval[slen] := 0X; sym := S_STRING; RETURN
      END
    ELSE
      IF slen < 4095 THEN sval[slen] := CHR(ch); INC(slen) END;
      Adv
    END
  END
END ReadString;

PROCEDURE ReadCharLit;  (* 'c' ; '' = apostrophe *)
VAR c2: INTEGER;
BEGIN
  Adv; (* ouvrante *)
  IF (ch = -1) OR (ch = 10) THEN Error("unterminated char literal") END;
  IF ch = 39 (* ' *) THEN
    c2 := Files.ReadByte(f);
    IF c2 = 39 THEN cval := 39; Adv; Adv; sym := S_CHAR; RETURN END;
    Error("empty char literal")
  END;
  cval := ch;
  Adv;
  IF ch # 39 THEN Error("unterminated char literal") END;
  Adv;
  sym := S_CHAR
END ReadCharLit;

PROCEDURE NextReal;
VAR c2: INTEGER; skip: BOOLEAN;
BEGIN
  skip := TRUE;
  WHILE skip DO
    IF ch = -1 THEN sym := S_EOF; RETURN END;
    IF (ch = 32) OR (ch = 9) OR (ch = 13) OR (ch = 10) THEN Adv
    ELSIF ch = 40 (* '(' *) THEN
      c2 := Files.ReadByte(f);
      IF c2 = 42 (* '*' *) THEN SkipComment ELSE UnGet(c2); sym := S_LPAREN; Adv; RETURN END
    ELSE skip := FALSE END
  END;
  IF IsLetter(ch) THEN ReadIdent; RETURN END;
  IF IsDigit(ch) THEN ReadNumber; RETURN END;
  CASE ch OF
    34: ReadString
  | 39: ReadCharLit
  | 58 (* : *) : Adv; IF ch = 61 THEN Adv; sym := S_ASSIGN ELSE sym := S_COLON END
  | 46 (* . *) : Adv; IF ch = 46 THEN Adv; sym := S_DOTDOT ELSE sym := S_DOT END
  | 44: Adv; sym := S_COMMA
  | 59: Adv; sym := S_SEMI
  | 41: Adv; sym := S_RPAREN
  | 91: Adv; sym := S_LBRACK
  | 93: Adv; sym := S_RBRACK
  | 94: Adv; sym := S_CARET
  | 123: Adv; sym := S_LBRACE
  | 125: Adv; sym := S_RBRACE
  | 43: Adv; sym := S_PLUS
  | 45: Adv; sym := S_MINUS
  | 42: Adv; sym := S_STAR
  | 47: Adv; sym := S_SLASH
  | 38: Adv; sym := S_AMP
  | 126: Adv; sym := S_TILDE
  | 124: Adv; sym := S_PIPE
  | 61: Adv; sym := S_EQ
  | 35: Adv; sym := S_NEQ
  | 60: Adv; IF ch = 61 THEN Adv; sym := S_LE ELSE sym := S_LT END
  | 62: Adv; IF ch = 61 THEN Adv; sym := S_GE ELSE sym := S_GT END
  ELSE Error("unexpected character")
  END
END NextReal;

PROCEDURE Next*;
BEGIN
  IF pbN > 0 THEN DEC(pbN); ApplyTok(pb[pbN])
  ELSE
    NextReal;
    RecordTok(hist[histCount MOD 8]);
    INC(histCount)
  END
END Next;

PROCEDURE Open*(path: ARRAY OF CHAR);
BEGIN
  f := Files.Open(path);
  IF f = NIL THEN Error("cannot open source file") END;
  line := 1; histCount := 0; pbN := 0; hasPushed := FALSE;
  Adv;
  Next
END Open;

PROCEDURE SymName*(s: INTEGER; VAR out: ARRAY OF CHAR);
BEGIN
  CASE s OF
    S_EOF: CopyStr("EOF", out, 256)
  | S_IDENT: CopyStr("ident", out, 256)
  | S_INT: CopyStr("int", out, 256)
  | S_REAL: CopyStr("real", out, 256)
  | S_CHAR: CopyStr("char", out, 256)
  | S_STRING: CopyStr("string", out, 256)
  | S_ARRAY: CopyStr("ARRAY", out, 256)
  | S_BEGIN: CopyStr("BEGIN", out, 256)
  | S_BY: CopyStr("BY", out, 256)
  | S_CASE: CopyStr("CASE", out, 256)
  | S_CONST: CopyStr("CONST", out, 256)
  | S_DIV: CopyStr("DIV", out, 256)
  | S_DO: CopyStr("DO", out, 256)
  | S_ELSE: CopyStr("ELSE", out, 256)
  | S_ELSIF: CopyStr("ELSIF", out, 256)
  | S_END: CopyStr("END", out, 256)
  | S_FOR: CopyStr("FOR", out, 256)
  | S_HALT: CopyStr("HALT", out, 256)
  | S_IF: CopyStr("IF", out, 256)
  | S_IMPORT: CopyStr("IMPORT", out, 256)
  | S_IN: CopyStr("IN", out, 256)
  | S_IS: CopyStr("IS", out, 256)
  | S_MOD: CopyStr("MOD", out, 256)
  | S_MODULE: CopyStr("MODULE", out, 256)
  | S_NIL: CopyStr("NIL", out, 256)
  | S_OF: CopyStr("OF", out, 256)
  | S_OR: CopyStr("OR", out, 256)
  | S_POINTER: CopyStr("POINTER", out, 256)
  | S_PROCEDURE: CopyStr("PROCEDURE", out, 256)
  | S_RECORD: CopyStr("RECORD", out, 256)
  | S_REPEAT: CopyStr("REPEAT", out, 256)
  | S_RETURN: CopyStr("RETURN", out, 256)
  | S_THEN: CopyStr("THEN", out, 256)
  | S_TO: CopyStr("TO", out, 256)
  | S_TYPE: CopyStr("TYPE", out, 256)
  | S_UNTIL: CopyStr("UNTIL", out, 256)
  | S_VAR: CopyStr("VAR", out, 256)
  | S_WHILE: CopyStr("WHILE", out, 256)
  | S_WITH: CopyStr("WITH", out, 256)
  | S_ASSIGN: CopyStr(":=", out, 256)
  | S_PLUS: CopyStr("+", out, 256)
  | S_MINUS: CopyStr("-", out, 256)
  | S_STAR: CopyStr("*", out, 256)
  | S_SLASH: CopyStr("/", out, 256)
  | S_AMP: CopyStr("&", out, 256)
  | S_TILDE: CopyStr("~", out, 256)
  | S_PIPE: CopyStr("|", out, 256)
  | S_EQ: CopyStr("=", out, 256)
  | S_NEQ: CopyStr("#", out, 256)
  | S_LT: CopyStr("<", out, 256)
  | S_LE: CopyStr("<=", out, 256)
  | S_GT: CopyStr(">", out, 256)
  | S_GE: CopyStr(">=", out, 256)
  | S_DOT: CopyStr(".", out, 256)
  | S_DOTDOT: CopyStr("..", out, 256)
  | S_COMMA: CopyStr(",", out, 256)
  | S_COLON: CopyStr(":", out, 256)
  | S_SEMI: CopyStr(";", out, 256)
  | S_LPAREN: CopyStr("(", out, 256)
  | S_RPAREN: CopyStr(")", out, 256)
  | S_LBRACK: CopyStr("[", out, 256)
  | S_RBRACK: CopyStr("]", out, 256)
  | S_CARET: CopyStr("^", out, 256)
  | S_LBRACE: CopyStr("{", out, 256)
  | S_RBRACE: CopyStr("}", out, 256)
  ELSE CopyStr("?", out, 256)
  END
END SymName;

END OCS.
