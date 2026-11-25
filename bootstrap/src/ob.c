#include "ob.h"

jmp_buf obJmp;
const char *obSrcName = "?";
int obLine = 1;

void obError(int line, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "%s:%d: error: ", obSrcName, line);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
  longjmp(obJmp, 1);
}

void bufInit(Buf *bf) { bf->b = NULL; bf->len = 0; bf->cap = 0; }

void bufPut(Buf *bf, const void *p, int n) {
  if (bf->len + n > bf->cap) {
    bf->cap = (bf->len + n) * 2 + 64;
    bf->b = realloc(bf->b, bf->cap);
    if (!bf->b) { fprintf(stderr, "out of memory\n"); exit(2); }
  }
  memcpy(bf->b + bf->len, p, n);
  bf->len += n;
}

void bufU8(Buf *bf, int v) { unsigned char c = (unsigned char)v; bufPut(bf, &c, 1); }

void bufU32(Buf *bf, uint32_t v) {
  unsigned char c[4] = { (unsigned char)v, (unsigned char)(v >> 8),
                         (unsigned char)(v >> 16), (unsigned char)(v >> 24) };
  bufPut(bf, c, 4);
}

void bufU64(Buf *bf, uint64_t v) {
  unsigned char c[8];
  for (int i = 0; i < 8; i++) c[i] = (unsigned char)(v >> (8 * i));
  bufPut(bf, c, 8);
}

Cell cellFromDouble(double d) {
  uint64_t u;
  memcpy(&u, &d, 8);
  return (Cell)u;
}

double cellToDouble(Cell c) {
  uint64_t u = (uint64_t)c;
  double d;
  memcpy(&d, &u, 8);
  return d;
}
