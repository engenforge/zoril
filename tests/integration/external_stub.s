.section .text
.global external_add
external_add:
    # rdi = a, rsi = b (SysV ABI)
    mov %edi, %eax
    add %esi, %eax
    ret

# Mark the stack non-executable; without this note GNU ld links the program with an executable stack.
.section .note.GNU-stack,"",@progbits
