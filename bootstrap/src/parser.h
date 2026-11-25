#ifndef PARSER_H
#define PARSER_H

#include "model.h"

/* Compile an open source file; dir = directory used to resolve imports.
   Returns the compiled module (caller serializes it). Aborts via longjmp on error. */
Module *compileSource(FILE *f, const char *srcName, const char *dir);

/* Compile srcPath to obcPath; returns 1 on success. Errors longjmp to local handler. */
int compileFile(const char *srcPath, const char *obcPath, const char *dir);

#endif
