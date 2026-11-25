/* obc.c - Oberon-07 bytecode compiler CLI
   usage: obc <file.Mod> [-o <file.obc>] */
#include "ob.h"
#include "model.h"
#include "parser.h"
#include "module.h"

int main(int argc, char **argv) {
  const char *in = NULL, *out = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
    else if (!in) in = argv[i];
    else { fprintf(stderr, "usage: obc <file.Mod> [-o <file.obc>]\n"); return 2; }
  }
  if (!in) { fprintf(stderr, "usage: obc <file.Mod> [-o <file.obc>]\n"); return 2; }
  initBasicTypes();
  FILE *f = fopen(in, "r");
  if (!f) { fprintf(stderr, "cannot open %s\n", in); return 1; }
  /* output path */
  char outPath[600];
  if (out) strncpy(outPath, out, sizeof outPath - 1);
  else {
    strncpy(outPath, in, sizeof outPath - 1);
    char *dot = strrchr(outPath, '.');
    if (dot) strcpy(dot, ".obc"); else strcat(outPath, ".obc");
  }
  /* dir of input for import resolution */
  char dir[600];
  strcpy(dir, ".");
  const char *slash = strrchr(in, '/');
  const char *bslash = strrchr(in, '\\');
  const char *sep = slash > bslash ? slash : bslash;
  if (sep) {
    size_t n = sep - in;
    if (n >= sizeof dir) n = sizeof dir - 1;
    memcpy(dir, in, n);
    dir[n] = 0;
  }
  if (setjmp(obJmp)) { fclose(f); return 1; }
  Module *m = compileSource(f, in, dir);
  fclose(f);
  FILE *o = fopen(outPath, "wb");
  if (!o) { fprintf(stderr, "cannot write %s\n", outPath); return 1; }
  writeModule(m, o);
  fclose(o);
  fprintf(stderr, "%s -> %s (%d procs, %d types, %d globals, %d strings)\n",
          in, outPath, m->nprocs, m->ntypes, m->globalSize, m->nstrings);
  return 0;
}
