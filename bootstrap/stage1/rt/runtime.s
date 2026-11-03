.section .text

.ifndef HOSTED
# 1. Entry Point
.global _start
_start:
    xor %rbp, %rbp
    
    mov (%rsp), %rdi    # argc
    lea 8(%rsp), %rsi   # argv

    # Record them where `args()` in stdlib/args.zrl can read them. These are the kernel's own
    # values, and the only code that ever sees the pointer is `args()`'s `unsafe` block.
    mov %edi, os_argc(%rip)
    mov %rsi, os_argv(%rip)
    
    # Save argc/argv
    mov %rdi, %r12
    mov %rsi, %r13
    
    # Align stack
    and $-16, %rsp

    # Restore argc/argv and call main
    mov %r12, %rdi
    mov %r13, %rsi
    call main
    
    mov %rax, %rdi      # exit code
    mov $231, %rax      # exit_group syscall
    syscall
    hlt
.else
# Hosted (`as --defsym HOSTED=1`, rt/runtime_hosted.o): crt1 enters through main(argc, argv). Store
# the arguments for `args()` and tail-call the program's entry, which `zoril --hosted` names
# zoril_main. Its result goes back to crt1, which calls exit. memcpy, memset, memcmp, write, abort,
# malloc and free are libc's: they are left out below.
.global main
main:
    mov %edi, os_argc(%rip)
    mov %rsi, os_argv(%rip)
    jmp zoril_main
.endif

# Process arguments, recorded by _start (or, hosted, main) and read by `args()` in stdlib/args.zrl. Accessors rather
# than exported globals: Zoril cannot declare a global that another object defines, and a stdlib
# global's symbol is mangled (`z12ICE_NOTE_LENE`), so asm cannot name one.
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

.global zoril_sys_syscall
zoril_sys_syscall:
    jmp __zoril_syscall_6

.ifndef HOSTED
# 3. Standard Library Helpers (Required for Linkage)
.global memcpy
.global zoril_memcpy
.global memset
.global zoril_memset

zoril_memset:
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx

memset:
    mov %rdi, %r11
    mov %rsi, %rax
    mov %rdx, %rcx
    rep stosb
    mov %r11, %rax
    ret

zoril_memcpy:
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx

memcpy:
    mov %rdi, %rax
    mov %rdx, %rcx
    cld
    rep movsb
    ret
.endif

# zoril_slice_eq(a_ptr, b_ptr, a_len, b_len, nbytes) -> bool
# Backs `==` / `!=` on slices of byte-comparable elements: equal lengths and equal
# contents over nbytes (= len * element size, computed by the caller). Plain byte loop
# assembled by host `as`.
.global zoril_slice_eq
zoril_slice_eq:
    xor %eax, %eax
    cmp %rdx, %rcx
    jne zoril_slice_eq_done
zoril_slice_eq_loop:
    test %r8, %r8
    jz zoril_slice_eq_true
    movzbq (%rdi), %rcx
    movzbq (%rsi), %rdx
    cmp %rdx, %rcx
    jne zoril_slice_eq_done
    add $1, %rdi
    add $1, %rsi
    sub $1, %r8
    jmp zoril_slice_eq_loop
zoril_slice_eq_true:
    mov $1, %eax
zoril_slice_eq_done:
    ret

.weak zoril_allocator_alloc
.global zoril_allocator_alloc
zoril_allocator_alloc:
    # rdi: env (ignored), rsi: arena (usually 0), rdx: size

    # mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    # size is in rdx, need it in rsi for syscall
    mov $9, %rax
    xor %rdi, %rdi
    mov %rdx, %rsi  # size
    mov $3, %rdx    # PROT_READ|PROT_WRITE
    mov $34, %r10   # MAP_PRIVATE|MAP_ANONYMOUS
    mov $-1, %r8
    xor %r9, %r9
    syscall
    ret


.ifndef HOSTED
.global memcmp
memcmp:
    # `cmpsb` compares the byte at %rsi with the byte at %rdi, while memcmp's sign is the
    # first argument (in %rdi) minus the second: without the swap the sign comes out inverted,
    # and with %rcx = 0 the `repe` leaves the flags of whatever ran before it, so n = 0 has to
    # return through the equal path. Both were found by scripts/check_runtimes.sh's probe
    # (2026-10-13): the two stage0-C copies got them right.
    test %rdx, %rdx
    je .L_memcmp_eq
    mov %rdx, %rcx
    xchg %rsi, %rdi
    repe cmpsb
    je .L_memcmp_eq
    ja .L_memcmp_gt
    mov $-1, %rax
    ret
.L_memcmp_gt:
    mov $1, %rax
    ret
.L_memcmp_eq:
    xor %rax, %rax
    ret

# 4. File I/O Helpers
.weak fd_open
.global fd_open
fd_open:
    mov $2, %rax    # open syscall
    # rdi already has path (*u8)
    mov $2, %rsi    # O_RDWR (typical value 2)
    mov $0644, %rdx # mode
    syscall
    ret

.weak fd_close
.global fd_close
fd_close:
    mov $3, %rax    # close syscall
    # rdi already has fd
    syscall
    ret

.weak write
.global write
write:
    mov $1, %rax    # write syscall
    # rdi, rsi, rdx already have arguments
    syscall
    ret
.endif

.global zoril_abort
zoril_abort:
    # write(2, "Aborted: reached unreachable code\n", 34)
    mov $1, %rax
    mov $2, %rdi
    lea .L_msg_abort(%rip), %rsi
    mov $34, %rdx
    syscall
    # exit(1)
    mov $231, %rax
    mov $1, %rdi
    syscall

.ifndef HOSTED
.global abort
abort:
    mov $231, %rax
    mov $134, %rdi
    syscall
.endif

# 6. Async I/O (io_uring) Wrappers
# __zoril_async_setup(entries: u64) -> u64 (ring fd, or 0 on error)
.global __zoril_async_setup
__zoril_async_setup:
    push %rbx
    mov %rdi, %rbx          # save entries
    sub $128, %rsp          # allocate io_uring_params on stack
    # zero-initialize params
    cld
    mov %rsp, %rdi
    xor %eax, %eax
    mov $128, %rcx
    rep stosb
    # io_uring_setup(entries, params) = syscall 425
    mov $425, %rax
    mov %rbx, %rdi          # entries
    mov %rsp, %rsi          # params ptr
    syscall
    add $128, %rsp          # free params
    pop %rbx
    test %rax, %rax
    jl .L_async_setup_err
    ret
.L_async_setup_err:
    xor %rax, %rax          # return 0 on error
    ret

# __zoril_async_enter(ring_fd: u64, to_submit: u32, min_complete: u32) -> u64
.global __zoril_async_enter
__zoril_async_enter:
    test %rdi, %rdi
    jz .L_async_enter_err
    # io_uring_enter(fd, to_submit, min_complete, flags=0, sig=NULL, sig_sz=0) = syscall 426
    movl %esi, %esi         # zero-extend to_submit (w) to 64-bit
    movl %edx, %edx         # zero-extend min_complete (w) to 64-bit
    mov $426, %rax
    xor %r10, %r10          # flags = 0
    xor %r8, %r8            # sig = NULL
    xor %r9, %r9            # sig_sz = 0
    syscall
    test %rax, %rax
    jl .L_async_enter_err
    ret
.L_async_enter_err:
    xor %rax, %rax
    ret

# __zoril_async_close(ring_fd: u64)
.global __zoril_async_close
__zoril_async_close:
    test %rdi, %rdi
    jz .L_async_close_done
    mov $3, %rax            # close syscall
    syscall
.L_async_close_done:
    ret

.ifndef HOSTED
.section .text
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
    # Unmaps the block malloc made: the mapping starts 16 bytes before the pointer handed out
    # (see malloc above) and is size + 32 long. This used to shift the address and the length
    # right by 3 before the syscall, so munmap got an address that is not page-aligned and
    # always failed with EINVAL: every free leaked. Found by the probe in
    # scripts/check_runtimes.sh (2026-10-13).
    testq %rdi, %rdi
    je .L_free_done
    movq -16(%rdi), %rdx
    leaq -16(%rdi), %rsi
    addq $32, %rdx
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

.endif
.section .rodata
.L_msg_abort: .ascii "Aborted: reached unreachable code\n"

# Process arguments, recorded by _start for zoril_argc / zoril_argv above.
.section .bss
.align 8
os_argv: .zero 8
os_argc: .zero 4

# Mark the stack non-executable: without this note GNU ld assumes the object needs an executable stack
# and links every program GNU_STACK RWE.
.section .note.GNU-stack,"",@progbits
