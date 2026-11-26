/* ob.h - common definitions for the Oberon-07 bytecode compiler and VM */
#ifndef OB_H
#define OB_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <setjmp.h>

/* A VM cell: 64 bits. Holds int32, double bits, heap ref, bool, char, set. */
typedef int64_t Cell;

/* Runtime opcodes */
enum {
  OP_NOP = 0,
  OP_CONST_I, OP_CONST_R, OP_CONST_S,          /* push const (i32 / f64 / string pool idx u32) */
  OP_LOAD_LOCAL, OP_STORE_LOCAL, OP_ADDR_LOCAL, /* u32 operand: (leveldiff<<16)|offset */
  OP_LOAD_GLOBAL, OP_STORE_GLOBAL, OP_ADDR_GLOBAL, /* u8 mod, u32 offset */
  OP_LOAD_AT, OP_STORE_AT, OP_TO_ADDR,          /* indirect via tagged address; TO_ADDR: heap ref -> tagged addr */
  OP_IADD, OP_ISUB, OP_IMUL, OP_IDIV, OP_IMOD, OP_INEG, OP_IABS, OP_IODD,
  OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FNEG, OP_FABS, OP_FFLOOR,
  OP_I2F, OP_F2I,
  OP_ILT, OP_ILE, OP_IGT, OP_IGE, OP_IEQ, OP_INE,
  OP_FLT, OP_FLE, OP_FGT, OP_FGE, OP_FEQ, OP_FNE,
  OP_EQ, OP_NE,                                 /* generic 1-cell equality */
  OP_AND, OP_OR, OP_NOT,
  OP_SET_UNION, OP_SET_DIFF, OP_SET_INTER, OP_SET_MEMBER,
  OP_JMP, OP_JZ, OP_JNZ,                        /* u32 target */
  OP_CALL,                                      /* u32 mod, u32 proc, u32 static-link steps */
  OP_RET,
  OP_NEW,                                       /* u8 mod, u32 typeidx : allocate record for pointer type */
  OP_ALLOC_ARRAY,                               /* u8 mod, u32 typeidx : allocate array object, push ref */
  OP_LEN,                                       /* u32 dim : pop array ref, push length of dim */
  OP_ISTYPE, OP_CHECKTYPE,                      /* u8 mod, u32 typeidx (record type) */
  OP_ELEM_ADDR,                                 /* pop flat index, pop array ref -> tagged addr of element */
  OP_COPY,                                      /* u32 ncells : pop src addr, pop dst addr, copy */
  OP_COPY_STR,                                  /* pop src ref, pop dst ref : copy min(srcdim,dstdim) cells */
  OP_DUP, OP_DROP, OP_SWAP,
  OP_SHL, OP_SHR,
  OP_AADD,                                      /* 64-bit add for tagged address arithmetic */
  OP_CONST_L,                                   /* push 64-bit integer (8 bytes) */
  OP_LADD, OP_LSUB, OP_LMUL, OP_LDIV, OP_LMOD, OP_LNEG, OP_LABS, OP_LODD,
  OP_LLT, OP_LLE, OP_LGT, OP_LGE, OP_LEQ, OP_LNE,
  OP_L2I,                                       /* LONGINT -> INTEGER (truncate) */
  OP_JUMPTABLE,                                 /* superinstruction: u32 n, u32 base, u32 default, n x u32 targets; pop selector, jump */
  OP_DISPOSE,                                   /* u8 mod, u32 typeidx (pointer type): pop slot addr, free object, store NIL */
  OP_PROCVAL,                                   /* u32 lmod, u32 procIdx : push procedure value (tagged cell TAG_PROC) */
  OP_CALLP,                                     /* pop procedure value, indirect call (args already on stack below it) */
  OP_COUNT
};

/* Address tagging (top byte of an address cell) */
#define TAG_STACK 0x00
#define TAG_GLOBAL 0x01
#define TAG_HEAP 0x02
#define TAG_PROC 0x03
#define ADDR_TAG(a) ((uint64_t)(a) >> 56)
#define MK_STACK_ADDR(idx)   ((Cell)(uint64_t)(idx))
#define MK_GLOBAL_ADDR(mod, off) ((Cell)(((uint64_t)TAG_GLOBAL << 56) | ((uint64_t)(mod) << 48) | (uint64_t)(off)))
#define MK_HEAP_ADDR(idx)    ((Cell)(((uint64_t)TAG_HEAP << 56) | (uint64_t)(idx)))
/* Procedure value: [tag 0x03][gid 8 bits][proc index 32 bits] */
#define MK_PROC(g, p)        ((Cell)(((uint64_t)TAG_PROC << 56) | ((uint64_t)(g) << 48) | (uint64_t)(uint32_t)(p)))
#define PROC_GID(c)          ((int)(((uint64_t)(c) >> 48) & 0xFF))
#define PROC_IDX(c)          ((int)((uint64_t)(c) & 0xFFFFFFFFu))

/* Growable byte buffer */
typedef struct { unsigned char *b; int len, cap; } Buf;
void bufPut(Buf *bf, const void *p, int n);
void bufU8(Buf *bf, int v);
void bufU32(Buf *bf, uint32_t v);
void bufU64(Buf *bf, uint64_t v);
void bufInit(Buf *bf);

/* Error handling: prints file:line and aborts compilation via longjmp */
extern jmp_buf obJmp;
extern const char *obSrcName;
extern int obLine;
void obError(int line, const char *fmt, ...);

/* double <-> Cell */
Cell cellFromDouble(double d);
double cellToDouble(Cell c);

#endif
