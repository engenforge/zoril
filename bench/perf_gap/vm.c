/* The vm.zrl interpreter in C: tagged union instructions, switch dispatch. */
#include <stdint.h>
#include <stddef.h>
#ifndef SCALE
#define SCALE 30000000
#endif
enum { PUSH, ADD, DUP, DEC, JNZ, POP, HALT };
typedef struct { int tag; int64_t v; } Op;
static int64_t run(const Op *code, int64_t n) {
    int64_t stack[64] = {0};
    size_t sp = 1, pc = 0;
    int64_t acc = 0;
    stack[0] = n;
    for (;;) {
        Op op = code[pc];
        switch (op.tag) {
        case PUSH: stack[sp++] = op.v; pc++; break;
        case ADD: sp--; stack[sp-1] = stack[sp-1] + stack[sp]; pc++; break;
        case DUP: stack[sp] = stack[sp-1]; sp++; pc++; break;
        case DEC: stack[sp-1] = stack[sp-1] - 1; pc++; break;
        case JNZ: sp--; if (stack[sp] != 0) pc = (size_t)op.v; else pc++; break;
        case POP: sp--; acc += stack[sp]; pc++; break;
        case HALT: return acc + stack[0];
        }
    }
}
int main(void) {
    Op code[8] = {{DUP,0},{PUSH,3},{ADD,0},{POP,0},{DEC,0},{DUP,0},{JNZ,0},{HALT,0}};
    int64_t r = run(code, SCALE);
    return (int)(r % 251);
}
