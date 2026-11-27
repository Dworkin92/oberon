/* ffi_glue.c - FFI generique (niveau 2) : appel de fonctions C dans des DLL
 * chargeables a l'execution, depuis Oberon, via le module SYSTEM (ids 80..89).
 *
 *   80 CALLC(fn: LONGINT; n: INTEGER; a0..a7: LONGINT): LONGINT
 *         appelle le pointeur de fonction C `fn` avec n (0..8) arguments
 *         64 bits (entiers/pointeurs -> registres RCX/RDX/R8/R9 puis pile,
 *         retour dans RAX).  Les flottants ne passent PAS (XMM) : pour une
 *         fonction C avec args/retour double, ecrire un wrapper C mince.
 *   81 LOADLIB(path: ARRAY OF CHAR): LONGINT   (LoadLibraryA, 0 si echec)
 *   82 SYMBOL(lib: LONGINT; name: ARRAY OF CHAR): LONGINT  (GetProcAddress)
 *   83 FREELIB(lib: LONGINT)                   (FreeLibrary)
 *   84 CSTR(s: ARRAY OF CHAR): LONGINT         (copie C NUL malloc'ee)
 *   85 STR(p: LONGINT; VAR buf: ARRAY OF CHAR) (copie la chaine C dans buf)
 *   86 MALLOC(size: LONGINT): LONGINT
 *   87 FREE(p: LONGINT)
 *   88 PEEK(p: LONGINT): LONGINT               (lit 8 octets a l'adresse p)
 *   89 POKE(p, v: LONGINT)                     (ecrit 8 octets)
 *
 * Un seul endroit (rt.c:callBuiltin, id >= 80) couvre obvm, le natif ob2c
 * et la VM.Mod (qui forward via ses wrappers CallBuiltin).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <windows.h>
#include "rt.h"

typedef int64_t (*F0)(void);
typedef int64_t (*F1)(int64_t);
typedef int64_t (*F2)(int64_t, int64_t);
typedef int64_t (*F3)(int64_t, int64_t, int64_t);
typedef int64_t (*F4)(int64_t, int64_t, int64_t, int64_t);
typedef int64_t (*F5)(int64_t, int64_t, int64_t, int64_t, int64_t);
typedef int64_t (*F6)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
typedef int64_t (*F7)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);
typedef int64_t (*F8)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t, int64_t);

/* appel C a n args 64 bits ; le compilateur genere l'appel ABI Windows x64
 * correct (registres + pile + alignement) via les prototypes fixes ci-dessus */
static Cell callC(VM *vm, Cell fn, int n, Cell *a) {
  if (n < 0 || n > 8) vmRuntimeError(vm, "CALLC: n must be 0..8");
  switch (n) {
    case 0: return ((F0)(intptr_t)fn)();
    case 1: return ((F1)(intptr_t)fn)(a[0]);
    case 2: return ((F2)(intptr_t)fn)(a[0], a[1]);
    case 3: return ((F3)(intptr_t)fn)(a[0], a[1], a[2]);
    case 4: return ((F4)(intptr_t)fn)(a[0], a[1], a[2], a[3]);
    case 5: return ((F5)(intptr_t)fn)(a[0], a[1], a[2], a[3], a[4]);
    case 6: return ((F6)(intptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5]);
    case 7: return ((F7)(intptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5], a[6]);
    default: return ((F8)(intptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
  }
}

/* cell-array (1 char/cellule) -> C string */
static void refToCStr(VM *vm, Cell ref, char *buf, int max) {
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

/* C string -> cell-array ; slotAddr = adresse du slot de la variable tableau */
static void cStrToRef(VM *vm, Cell slotAddr, const char *s) {
  Cell ref = memRead(vm, slotAddr);
  if (!ref) return;
  int ndim = (int)-vm->heap[ref];
  int total = (int)vm->heap[ref + ndim + 1];
  int hdr = ndim + 2;
  int n = s ? (int)strlen(s) : 0;
  if (n > total - 1) n = total - 1;
  for (int i = 0; i < n; i++) vm->heap[ref + hdr + i] = (unsigned char)s[i];
  vm->heap[ref + hdr + n] = 0;
}

int ffiBuiltin(VM *vm, int id, Cell *arg, int base) {
  char nm[1024];
  switch (id) {
    case 80: /* CALLC(fn, n, a0..a7): LONGINT */
      vm->stack[base] = callC(vm, arg[0], (int)(int32_t)arg[1], &arg[2]);
      return 1;
    case 81: /* LOADLIB(path): LONGINT */
      refToCStr(vm, arg[0], nm, sizeof nm);
      vm->stack[base] = (Cell)(intptr_t)LoadLibraryA(nm);
      return 1;
    case 82: /* SYMBOL(lib, name): LONGINT */
      refToCStr(vm, arg[1], nm, sizeof nm);
      vm->stack[base] = (Cell)(intptr_t)GetProcAddress((HMODULE)(intptr_t)arg[0], nm);
      return 1;
    case 83: /* FREELIB(lib) */
      if (arg[0]) FreeLibrary((HMODULE)(intptr_t)arg[0]);
      return 1;
    case 84: { /* CSTR(s): LONGINT — copie C malloc'ee */
      char *p;
      refToCStr(vm, arg[0], nm, sizeof nm);
      p = (char *)malloc(strlen(nm) + 1);
      if (p) strcpy(p, nm);
      vm->stack[base] = (Cell)(intptr_t)p;
      return 1;
    }
    case 85: /* STR(p, VAR buf) */
      cStrToRef(vm, arg[1], (const char *)(intptr_t)arg[0]);
      return 1;
    case 86: /* MALLOC(size): LONGINT */
      vm->stack[base] = (Cell)(intptr_t)malloc((size_t)arg[0]);
      return 1;
    case 87: /* FREE(p) */
      free((void *)(intptr_t)arg[0]);
      return 1;
    case 88: /* PEEK(p): LONGINT */
      vm->stack[base] = arg[0] ? *(Cell *)(intptr_t)arg[0] : 0;
      return 1;
    case 89: /* POKE(p, v) */
      if (arg[0]) *(Cell *)(intptr_t)arg[0] = arg[1];
      return 1;
  }
  return 0;
}
