#include "ob.h"
#include "lexer.h"

int sym;
long long ival;
double rval;
int cval;
char name[64];
char sval[4096];
int slen;
int line;

static FILE *src;
static int ch; /* lookahead char */

static void adv(void) {
  ch = fgetc(src);
  if (ch == '\n') { line++; obLine = line; }
}

static int isLetter(int c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
static int isDigit(int c) { return c >= '0' && c <= '9'; }

static struct { const char *kw; int s; } kwtab[] = {
  {"ARRAY", S_ARRAY}, {"BEGIN", S_BEGIN}, {"BY", S_BY}, {"CASE", S_CASE},
  {"CONST", S_CONST}, {"DIV", S_DIV}, {"DO", S_DO}, {"ELSE", S_ELSE},
  {"ELSIF", S_ELSIF}, {"END", S_END}, {"FOR", S_FOR},
  {"IF", S_IF}, {"IMPORT", S_IMPORT}, {"IN", S_IN}, {"IS", S_IS},
  {"MOD", S_MOD}, {"MODULE", S_MODULE}, {"NIL", S_NIL}, {"OF", S_OF},
  {"OR", S_OR}, {"POINTER", S_POINTER}, {"PROCEDURE", S_PROCEDURE},
  {"RECORD", S_RECORD}, {"REPEAT", S_REPEAT}, {"RETURN", S_RETURN},
  {"THEN", S_THEN}, {"TO", S_TO}, {"TYPE", S_TYPE}, {"UNTIL", S_UNTIL},
  {"VAR", S_VAR}, {"WHILE", S_WHILE}, {"WITH", S_WITH}, {NULL, 0}
};

static int kwLookup(const char *s) {
  /* Oberon keywords are case-sensitive (uppercase) */
  for (int i = 0; kwtab[i].kw; i++)
    if (strcmp(kwtab[i].kw, s) == 0) return kwtab[i].s;
  return S_IDENT;
}

void lexInit(FILE *f, const char *srcName) {
  src = f;
  obSrcName = srcName;
  line = 1;
  obLine = 1;
  adv();
}

static void skipComment(void) {
  /* ch == '(' and next is '*'; nested comments */
  int depth = 1;
  adv(); adv();
  while (depth > 0) {
    if (ch == EOF) obError(line, "unterminated comment");
    if (ch == '(') {
      int c2 = fgetc(src);
      if (c2 == '*') { depth++; adv(); continue; } /* ch='(' et c2='*' déjà consommés : un seul adv suffit */
      ungetc(c2, src);
      adv();
    } else if (ch == '*') {
      int c2 = fgetc(src);
      if (c2 == ')') { depth--; adv(); continue; } /* idem après '*' ')' : ne pas manger le caractère suivant */
      ungetc(c2, src);
      adv();
    } else {
      adv();
    }
  }
}

static void readNumber(void) {
  char buf[128];
  int n = 0;
  int isReal = 0, isHex = 0, isChar = 0;
  while (isDigit(ch) || (ch >= 'A' && ch <= 'F') || (ch >= 'a' && ch <= 'f') || ch == '.') {
    if (ch == '.') {
      /* ".." is range, not part of number */
      int c2 = fgetc(src);
      if (c2 == '.') { ungetc(c2, src); break; }
      ungetc(c2, src);
      if (isHex) break; /* hex has no dot */
      isReal = 1;
      buf[n++] = '.';
      adv();
      continue;
    }
    if (ch >= 'a' && ch <= 'f') {
      if (ch == 'e' || ch == 'E') {
        /* could be exponent: digit before, digits after */
        int c2 = fgetc(src);
        if (isDigit(c2) || ((c2 == '+' || c2 == '-') )) {
          /* exponent of real: only if we already have a dot or it's like 1E3 */
          if (!isHex) { isReal = 1; buf[n++] = 'E'; adv(); 
            if (ch == '+' || ch == '-') { buf[n++] = (char)ch; adv(); }
            continue;
          }
        }
        ungetc(c2, src);
        isHex = 1; buf[n++] = 'E'; adv(); continue;
      }
      isHex = 1;
      buf[n++] = (char)(ch - 32);
      adv();
      continue;
    }
    if (ch >= 'A' && ch <= 'F') {
      if (ch == 'E') {
        int c2 = fgetc(src);
        if (!isHex && (isDigit(c2) || c2 == '+' || c2 == '-')) {
          isReal = 1; buf[n++] = 'E'; adv();
          if (ch == '+' || ch == '-') { buf[n++] = (char)ch; adv(); }
          continue;
        }
        ungetc(c2, src);
      }
      isHex = 1;
      buf[n++] = (char)ch;
      adv();
      continue;
    }
    buf[n++] = (char)ch;
    adv();
  }
  /* suffixes */
  if (ch == 'H') { isHex = 1; adv(); }
  else if (ch == 'X') { isChar = 1; isHex = 1; adv(); }
  else if (ch >= 'a' && ch <= 'z') {
    if (ch == 'h') { isHex = 1; adv(); }
    else if (ch == 'x') { isChar = 1; isHex = 1; adv(); }
  }
  buf[n] = 0;
  if (isChar) {
    sym = S_CHAR;
    cval = (int)strtol(buf, NULL, 16);
    return;
  }
  if (isReal) {
    sym = S_REAL;
    rval = strtod(buf, NULL);
    return;
  }
  if (isHex) {
    sym = S_INT;
    ival = strtoll(buf, NULL, 16);
    return;
  }
  sym = S_INT;
  ival = strtoll(buf, NULL, 10);
}

static void readIdent(void) {
  int n = 0;
  while (isLetter(ch) || isDigit(ch)) {
    if (n < 63) name[n++] = (char)ch;
    adv();
  }
  name[n] = 0;
  sym = kwLookup(name);
}

static void readString(void) {
  adv(); /* opening quote */
  slen = 0;
  for (;;) {
    if (ch == EOF || ch == '\n') obError(line, "unterminated string");
    if (ch == '"') {
      int c2 = fgetc(src);
      if (c2 == '"') { /* doubled quote = literal " */
        if (slen < 4095) sval[slen++] = '"';
        adv(); adv();
        continue;
      }
      ungetc(c2, src);
      adv();
      break;
    }
    if (slen < 4095) sval[slen++] = (char)ch;
    adv();
  }
  sval[slen] = 0;
  sym = S_STRING;
}

static void readCharLit(void) {
  adv(); /* opening ' */
  if (ch == EOF || ch == '\n') obError(line, "unterminated char literal");
  if (ch == '\'') {
    int c2 = fgetc(src);
    if (c2 == '\'') { cval = '\''; adv(); adv(); sym = S_CHAR; return; }
    obError(line, "empty char literal");
  }
  cval = ch;
  adv();
  if (ch != '\'') obError(line, "unterminated char literal");
  adv();
  sym = S_CHAR;
}

/* ---- token pushback for lexSave/lexRestore ---- */
#define PBMAX 16
#define HISTMAX 64
static LexTok pb[PBMAX]; static int pbN;
static LexTok hist[HISTMAX]; static long histCount;

static void tokRecord(LexTok *t) {
  t->sym = sym; t->line = line; t->obLine = obLine;
  t->ival = ival; t->rval = rval; t->cval = cval;
  memcpy(t->name, name, 64); memcpy(t->sval, sval, 4096); t->slen = slen;
}
static void tokApply(const LexTok *t) {
  sym = t->sym; line = t->line; obLine = t->obLine;
  ival = t->ival; rval = t->rval; cval = t->cval;
  memcpy(name, t->name, 64); memcpy(sval, t->sval, 4096); slen = t->slen;
}

void lexSave(LexState *s) {
  tokRecord(&s->tok);
  s->src = src; s->ch = ch;
  s->histMark = histCount;
  s->srcName = obSrcName; s->obLine = obLine;
}
void lexRestore(const LexState *s) {
  tokApply(&s->tok);
  obSrcName = s->srcName; obLine = s->obLine;
  if (s->src == src) {
    /* same input file: replay the tokens consumed since the save from the
       history; ch and the file position are already past them, keep them */
    pbN = 0;
    for (long i = histCount - 1; i >= s->histMark; i--) {
      if (pbN < PBMAX) pb[pbN++] = hist[i % HISTMAX];
    }
  } else {
    /* nested-import case: the stream was switched, restore it wholesale */
    src = s->src; ch = s->ch;
  }
}
const char *symName(int s) {
  static const char *names[] = {
    "EOF", "ident", "int", "real", "char", "string",
    "ARRAY", "BEGIN", "BY", "CASE", "CONST", "DIV", "DO", "ELSE", "ELSIF",
    "END", "FOR", "HALT", "IF", "IMPORT", "IN", "IS", "MOD", "MODULE", "NIL",
    "OF", "OR", "POINTER", "PROCEDURE", "RECORD", "REPEAT", "RETURN", "THEN",
    "TO", "TYPE", "UNTIL", "VAR", "WHILE", "WITH",
    ":=", "+", "-", "*", "/", "&", "~", "|", "=", "#", "<", "<=", ">", ">=",
    ".", "..", ",", ":", ";", "(", ")", "[", "]", "^", "{", "}"
  };
  if (s >= 0 && s <= S_RBRACE) return names[s];
  return "?";
}

static void nextSymReal(void) {
  for (;;) {
    if (ch == EOF) { sym = S_EOF; return; }
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') { adv(); continue; }
    if (ch == '(') {
      int c2 = fgetc(src);
      if (c2 == '*') { skipComment(); continue; }
      ungetc(c2, src);
      sym = S_LPAREN; adv(); return;
    }
    break;
  }
  if (isLetter(ch)) { readIdent(); return; }
  if (isDigit(ch)) { readNumber(); return; }
  switch (ch) {
    case '"': readString(); return;
    case '\'': readCharLit(); return;
    case ':': adv(); if (ch == '=') { adv(); sym = S_ASSIGN; } else sym = S_COLON; return;
    case '.': adv(); if (ch == '.') { adv(); sym = S_DOTDOT; } else sym = S_DOT; return;
    case ',': adv(); sym = S_COMMA; return;
    case ';': adv(); sym = S_SEMI; return;
    case ')': adv(); sym = S_RPAREN; return;
    case '[': adv(); sym = S_LBRACK; return;
    case ']': adv(); sym = S_RBRACK; return;
    case '^': adv(); sym = S_CARET; return;
    case '{': adv(); sym = S_LBRACE; return;
    case '}': adv(); sym = S_RBRACE; return;
    case '+': adv(); sym = S_PLUS; return;
    case '-': adv(); sym = S_MINUS; return;
    case '*': adv(); sym = S_STAR; return;
    case '/': adv(); sym = S_SLASH; return;
    case '&': adv(); sym = S_AMP; return;
    case '~': adv(); sym = S_TILDE; return;
    case '|': adv(); sym = S_PIPE; return;
    case '=': adv(); sym = S_EQ; return;
    case '#': adv(); sym = S_NEQ; return;
    case '<': adv(); if (ch == '=') { adv(); sym = S_LE; } else sym = S_LT; return;
    case '>': adv(); if (ch == '=') { adv(); sym = S_GE; } else sym = S_GT; return;
    default:
      obError(line, "unexpected character '%c' (0x%02x)", ch, ch);
  }
}

void nextSym(void) {
  if (pbN > 0) { tokApply(&pb[--pbN]); return; }
  nextSymReal();
  tokRecord(&hist[histCount % HISTMAX]);
  histCount++;
}
