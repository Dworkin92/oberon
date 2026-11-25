/* obvm.c - Oberon bytecode VM CLI
   usage: obvm <file.obc> */
#include "ob.h"
#include "model.h"
#include "vm.h"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: obvm <file.obc>\n"); return 2; }
#ifdef _WIN32
  /* binary mode so Out.Byte / In.Byte work on raw bytes */
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stdin), _O_BINARY);
#endif
  initBasicTypes();
  if (setjmp(obJmp)) return 1;
  VM *vm = vmLoad(argv[1]);
  vmSetArgs(argc - 2, argv + 2); /* args after the .obc path = program args */
  vmRun(vm);
  fflush(stdout);
  return vm->haltCode;
}
