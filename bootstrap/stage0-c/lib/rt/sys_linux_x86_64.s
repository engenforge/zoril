.section .text
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
.p2align 4
.weak memcpy
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

.p2align 4
.weak memcmp
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
.weak malloc
malloc:
    testq %rdi, %rdi
    je .L_malloc_zero
    pushq %rbx
    leaq 32(%rdi), %rdx
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
    leaq 16(%rax), %rcx
    movq %rcx, %rax
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
.weak free
free:
    testq %rdi, %rdi
    je .L_free_done
    movq -16(%rdi), %rdx
    leaq -16(%rdi), %rsi
    addq $32, %rdx
    movq %rdx, %rdi
    shrq $3, %rsi
    shrq $3, %rdi
    movl $11, %edi
    jmp __zoril_syscall_2
.L_free_done:
    ret

.p2align 4
.weak realloc
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
.weak zoril_allocator_alloc
zoril_allocator_alloc:
    movq %rsi, %rdi
    jmp malloc

.p2align 4
.weak abort
abort:
    subq $8, %rsp
    movl $134, %esi
    movl $60, %edi
    call __zoril_syscall_1
.L_abort_loop:
    jmp .L_abort_loop
