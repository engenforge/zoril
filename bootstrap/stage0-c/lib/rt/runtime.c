// Freestanding Zoril Runtime Environment
// No C standard library dependencies.

#include <stdint.h>
typedef unsigned long size_t;
typedef long ssize_t;
#define NULL ((void*)0)

void abort(void);

// 1. Direct System Call Stubs (Declarations only, implemented in sys.s)
extern long __zoril_syscall_0(long n);
extern long __zoril_syscall_1(long n, long a1);
extern long __zoril_syscall_2(long n, long a1, long a2);
extern long __zoril_syscall_3(long n, long a1, long a2, long a3);
extern long __zoril_syscall_4(long n, long a1, long a2, long a3, long a4);
extern long __zoril_syscall_5(long n, long a1, long a2, long a3, long a4, long a5);
extern long __zoril_syscall_6(long n, long a1, long a2, long a3, long a4, long a5, long a6);

// 2. Memory Utilities
void* memcpy(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

void* memset(void* dest, int c, size_t n) {
    unsigned char* d = (unsigned char*)dest;
    for (size_t i = 0; i < n; i++) {
        d[i] = (unsigned char)c;
    }
    return dest;
}

int memcmp(const void* s1, const void* s2, size_t n) {
    const unsigned char* p1 = (const unsigned char*)s1;
    const unsigned char* p2 = (const unsigned char*)s2;
    for (size_t i = 0; i < n; i++) {
        if (p1[i] != p2[i]) {
            return p1[i] - p2[i];
        }
    }
    return 0;
}

// 3. Built-in Allocator for global 'box' and vectors
// Syscall 9: mmap, Syscall 11: munmap
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define MAP_PRIVATE 0x02
#define MAP_ANONYMOUS 0x20

void* malloc(size_t size) {
    if (size == 0) return NULL;
    size_t total = size + 16;
    long ret = __zoril_syscall_6(9, 0, total, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ret < 0 && ret > -4096) return NULL;
    size_t* block = (size_t*)ret;
    *block = size;
    uint64_t raw_ptr = (uint64_t)ret;
    return (void*)(raw_ptr + 16);
}

void free(void* ptr) {
    if (!ptr) return;
    uint64_t raw_ptr = (uint64_t)ptr - 16;
    size_t* block = (size_t*)raw_ptr;
    size_t size = *block;
    __zoril_syscall_2(11, (long)raw_ptr, size + 16);
}

void* realloc(void* ptr, size_t size) {
    if (!ptr) return malloc(size);
    if (size == 0) { free(ptr); return NULL; }
    uint64_t raw_ptr = (uint64_t)ptr - 16;
    size_t* block = (size_t*)raw_ptr;
    size_t old_size = *block;
    void* new_ptr = malloc(size);
    if (new_ptr) {
        char* d = (char*)new_ptr;
        char* s = (char*)ptr;
        size_t n = old_size < size ? old_size : size;
        for (size_t i = 0; i < n; i++) d[i] = s[i];
        free(ptr);
    }
    return new_ptr;
}

void* zoril_allocator_alloc(void* allocator_ptr, size_t size) {
    (void)allocator_ptr;
    return malloc(size);
}

// 4. Panic and Abort
void abort(void) {
    __zoril_syscall_1(60, 134); // exit(134) for SIGABRT
    while(1);
}

// Called by stdlib/core0.zrl (user panics) and vec.zrl (bounds failures); same exit status as abort.
void zoril_abort(void) {
    abort();
}

static size_t runtime_strlen(const char* s) {
    size_t len = 0;
    while (s[len]) len++;
    return len;
}

void zoril_panic(const char* msg) {
    const char* p = "panic: ";
    __zoril_syscall_3(1, 2, (long)p, 7); // write to stderr
    __zoril_syscall_3(1, 2, (long)msg, runtime_strlen(msg));
    __zoril_syscall_3(1, 2, (long)"\n", 1);
    abort();
}

/* The process arguments, recorded by _start below and read by `args()` in stdlib/args.zrl - the C
   twin of os_argc/os_argv in rt/runtime.s. Not static: the _start asm below names them. */
int os_argc = 0;
char** os_argv = 0;

int zoril_argc(void);
char** zoril_argv(void);

int zoril_argc(void) { return os_argc; }
char** zoril_argv(void) { return os_argv; }

extern int main(int argc, char** argv);

__asm__(
    ".section .text\n"
    ".weak _start\n"
    ".global _start\n"
    "_start:\n"
    "    xor %rbp, %rbp\n"
    "    mov (%rsp), %rdi\n"
    "    lea 8(%rsp), %rsi\n"
    "    mov %edi, os_argc(%rip)\n"
    "    mov %rsi, os_argv(%rip)\n"
    "    and $-16, %rsp\n"
    "    call main\n"
    "    mov %rax, %rdi\n"
    "    mov $60, %rax\n"
    "    syscall\n"
    "    hlt\n"
);
