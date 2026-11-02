.section .text

# 1. Entry Point
.weak _start
.global _start
_start:
    xor %rbp, %rbp
    mov (%rsp), %rdi
    lea 8(%rsp), %rsi

    # Record them where `args()` in stdlib/args.zrl can read them (see rt/runtime.s).
    mov %edi, os_argc(%rip)
    mov %rsi, os_argv(%rip)

    and $-16, %rsp
    call main
    mov %rax, %rdi
    mov $60, %rax
    syscall
    hlt

# Process arguments, recorded by _start and read by `args()` in stdlib/args.zrl. Accessors rather
# than exported globals: Zoril cannot declare a global that another object defines, and a stdlib
# global's symbol is mangled, so asm cannot name one.
.global zoril_argc
zoril_argc:
    mov os_argc(%rip), %eax
    ret

.global zoril_argv
zoril_argv:
    mov os_argv(%rip), %rax
    ret

# 2. Syscall Stubs
.global __zoril_syscall_0
.global __zoril_syscall_1
.global __zoril_syscall_2
.global __zoril_syscall_3
.global __zoril_syscall_4
.global __zoril_syscall_5
.global __zoril_syscall_6

__zoril_syscall_0:
    mov %rdi, %rax
    syscall
    ret

__zoril_syscall_1:
    mov %rdi, %rax
    mov %rsi, %rdi
    syscall
    ret

__zoril_syscall_2:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    syscall
    ret

__zoril_syscall_3:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx
    syscall
    ret

__zoril_syscall_4:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx
    mov %r8, %r10
    syscall
    ret

__zoril_syscall_5:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx
    mov %r8, %r10
    mov %r9, %r8
    syscall
    ret

__zoril_syscall_6:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx
    mov %r8, %r10
    mov %r9, %r8
    mov 8(%rsp), %r9
    syscall
    ret

# 3. Runtime Functions
.p2align 4
.globl memcpy
memcpy:
    movq %rdi, %rax
    testq %rdx, %rdx
    je .L_memcpy_done
    xorl %ecx, %ecx
.L_memcpy_loop:
    movzbl (%rsi,%rcx), %r8d
    movb %r8b, (%rax,%rcx)
    addq $1, %rcx
    cmpq %rcx, %rdx
    jne .L_memcpy_loop
.L_memcpy_done:
    ret

# Same contract as the C twin: writes (unsigned char)value and hands back dest.
.p2align 4
.globl memset
memset:
    movq %rdi, %rax
    testq %rdx, %rdx
    je .L_memset_done
    xorl %ecx, %ecx
.L_memset_loop:
    movb %sil, (%rax,%rcx)
    addq $1, %rcx
    cmpq %rcx, %rdx
    jne .L_memset_loop
.L_memset_done:
    ret

.p2align 4
.globl memcmp
memcmp:
    testq %rdx, %rdx
    je .L_memcmp_zero
    xorl %eax, %eax
    jmp .L_memcmp_check
.L_memcmp_loop:
    addq $1, %rax
    cmpq %rax, %rdx
    je .L_memcmp_zero
.L_memcmp_check:
    movzbl (%rdi,%rax), %ecx
    movzbl (%rsi,%rax), %r8d
    cmpb %r8b, %cl
    je .L_memcmp_loop
    movzbl %cl, %eax
    subl %r8d, %eax
    ret
.L_memcmp_zero:
    xorl %eax, %eax
    ret

.p2align 4
.globl malloc
malloc:
    testq %rdi, %rdi
    je .L_malloc_zero
    pushq %rbx
    leaq 16(%rdi), %rdx
    movq $-1, %r9
    movq %rdi, %rbx
    movl $34, %r8d
    movl $3, %ecx
    xorl %esi, %esi
    movl $9, %edi
    subq $8, %rsp
    pushq $0
    call __zoril_syscall_6
    popq %r8
    popq %r9
    leaq 4095(%rax), %rdx
    cmpq $4094, %rdx
    jbe .L_malloc_fail
    movq %rbx, (%rax)
    leaq 16(%rax), %rax
.L_malloc_done:
    popq %rbx
    ret
.L_malloc_fail:
    xorl %eax, %eax
    popq %rbx
    ret
.L_malloc_zero:
    xorl %eax, %eax
    ret

.p2align 4
.globl free
free:
    testq %rdi, %rdi
    je .L_free_done
    movq -16(%rdi), %rdx
    leaq -16(%rdi), %rsi
    addq $16, %rdx
    movl $11, %edi
    jmp __zoril_syscall_2
.L_free_done:
    ret

.p2align 4
.globl realloc
realloc:
    pushq %r13
    pushq %r12
    pushq %rbp
    pushq %rbx
    movq %rsi, %rbx
    subq $8, %rsp
    testq %rdi, %rdi
    je .L_realloc_malloc
    movq %rdi, %rbp
    testq %rsi, %rsi
    je .L_realloc_free
    movq -16(%rdi), %r13
    movq %rsi, %rdi
    call malloc
    movq %rax, %r12
    testq %rax, %rax
    je .L_realloc_fail
    cmpq %r13, %rbx
    movq %r13, %rdi
    cmovbe %rbx, %rdi
    testq %rdi, %rdi
    je .L_realloc_copy_done
    xorl %edx, %edx
.L_realloc_copy_loop:
    movzbl 0(%rbp,%rdx), %ecx
    movb %cl, (%r12,%rdx)
    addq $1, %rdx
    cmpq %rdx, %rdi
    jne .L_realloc_copy_loop
.L_realloc_copy_done:
    movq %rbp, %rdi
    call free
    addq $8, %rsp
    movq %r12, %rax
    popq %rbx
    popq %rbp
    popq %r12
    popq %r13
    ret
.L_realloc_free:
    call free
.L_realloc_fail:
    addq $8, %rsp
    xorl %r12d, %r12d
    popq %rbx
    movq %r12, %rax
    popq %rbp
    popq %r12
    popq %r13
    ret
.L_realloc_malloc:
    addq $8, %rsp
    movq %rsi, %rdi
    popq %rbx
    popq %rbp
    popq %r12
    popq %r13
    jmp malloc

.p2align 4
.globl zoril_allocator_alloc
zoril_allocator_alloc:
    movq %rsi, %rdi
    jmp malloc

.p2align 4
# Called by stdlib/core0.zrl (user panics) and vec.zrl (bounds failures); same as abort.
.globl zoril_abort
zoril_abort:
.globl abort
abort:
    subq $8, %rsp
    movl $134, %esi
    movl $60, %edi
    call __zoril_syscall_1
.L_abort_loop:
    jmp .L_abort_loop

.p2align 4
.globl zoril_panic
zoril_panic:
    pushq %rbx
    movl $7, %ecx
    movq %rdi, %rbx
    movl $.L_msg_panic, %edx
    movl $2, %esi
    movl $1, %edi
    call __zoril_syscall_3
    xorl %ecx, %ecx
    cmpb $0, (%rbx)
    je .L_panic_msg
.L_panic_len_loop:
    addq $1, %rcx
    cmpb $0, (%rbx,%rcx)
    jne .L_panic_len_loop
.L_panic_msg:
    movq %rbx, %rdx
    movl $2, %esi
    movl $1, %edi
    call __zoril_syscall_3
    movl $1, %ecx
    movl $.L_msg_newline, %edx
    movl $2, %esi
    movl $1, %edi
    call __zoril_syscall_3
    call abort

.section .rodata
.L_msg_newline:   .string "\n"
.L_msg_panic:     .string "panic: "

# Process arguments, recorded by _start for zoril_argc / zoril_argv above.
.section .bss
.align 8
os_argv: .zero 8
os_argc: .zero 4
