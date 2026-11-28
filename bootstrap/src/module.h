#ifndef MODULE_IO_H
#define MODULE_IO_H

#include "model.h"

/* A module loaded from a .obc file (used by the compiler for imports,
   and by the VM at runtime). */
typedef struct LProc {
  char name[64];
  int exported, isBody;
  int nparams;
  Obj **params;      /* param objects */
  int nlocals;
  int hasResult;
  Type *result;
  unsigned char *code;
  int codelen;
} LProc;

typedef struct LoadedModule {
  char name[64];
  char **imports;
  int nimports;
  int globalSize;
  Obj *exportedVars;   /* linked list of CL_VAR */
  Type **types;
  int ntypes;
  LProc *procs;
  int nprocs;
  char **strings;
  int nstrings;
  Obj *members;        /* all exported members (procs/types/vars) for import resolution */
} LoadedModule;

void writeModule(Module *m, FILE *f);
LoadedModule *loadModuleFile(const char *path);
/* Search a compiled module `name` starting from dir `dir`:
   dir/name.obc, then dir/../lib/name.obc, then dir/../../lib/name.obc.
   On success writes the found path into out and returns 1, else returns 0. */
int findModuleFile(const char *name, const char *dir, int allowMod, char *out, int outsz);
int obExePath(char *buf, int cap);
void obOberonHome(char *buf, int cap);
int obSearchDirs(const char *fromDir, char dirs[][600], int maxDirs);
struct Module;
struct Type;
void registerTypeDeep(struct Module *m, struct Type *t); /* deep type registration (writeModule pre-pass) */
/* Build import symbol table (Obj CL_MODULE) from a loaded module */
Obj *moduleObjFromLoaded(LoadedModule *lm, int modId, int exportedOnly);

/* file helpers */
void wStr(FILE *f, const char *s);
void wU8(FILE *f, int v);
void wU32(FILE *f, uint32_t v);
int rU8(FILE *f);
uint32_t rU32(FILE *f);
char *rStr(FILE *f); /* malloc'd */

#endif
