#ifndef LEXER_H
#define LEXER_H

/* Symbols */
enum {
  S_EOF = 0, S_IDENT, S_INT, S_REAL, S_CHAR, S_STRING,
  /* keywords */
  S_ARRAY, S_BEGIN, S_BY, S_CASE, S_CONST, S_DIV, S_DO, S_ELSE, S_ELSIF,
  S_END, S_FOR, S_HALT, S_IF, S_IMPORT, S_IN, S_IS, S_MOD, S_MODULE, S_NIL,
  S_OF, S_OR, S_POINTER, S_PROCEDURE, S_RECORD, S_REPEAT, S_RETURN, S_THEN,
  S_TO, S_TYPE, S_UNTIL, S_VAR, S_WHILE, S_WITH,
  /* punctuation / operators */
  S_ASSIGN,   /* := */
  S_PLUS, S_MINUS, S_STAR, S_SLASH, S_AMP,
  S_TILDE, S_PIPE,
  S_EQ, S_NEQ, S_LT, S_LE, S_GT, S_GE,
  S_DOT, S_DOTDOT, S_COMMA, S_COLON, S_SEMI,
  S_LPAREN, S_RPAREN, S_LBRACK, S_RBRACK, S_CARET, S_LBRACE, S_RBRACE
};

const char *symName(int s);

extern int sym;             /* current symbol */
extern long long ival;      /* S_INT value */
extern double rval;         /* S_REAL value */
extern int cval;            /* S_CHAR value */
extern char name[64];       /* S_IDENT text */
extern char sval[4096];     /* S_STRING text */
extern int slen;
extern int line;

void lexInit(FILE *f, const char *srcName);
void nextSym(void);

/* save/restore lexer state (nested compilations of imported modules) */
typedef struct {
  FILE *src; int ch; int line; int sym;
  long long ival; double rval; int cval;
  char name[64]; char sval[4096]; int slen;
  const char *srcName; int obLine;
} LexState;
void lexSave(LexState *s);
void lexRestore(const LexState *s);

#endif
