.section .bss
    .align 8
kept_ptr:
    .zero 8

.section .text
.global keep
keep:
    mov %rdi, kept_ptr(%rip)
    ret

.global kept
kept:
    mov kept_ptr(%rip), %rax
    ret

.section .note.GNU-stack,"",@progbits
