.section .text
.global external_add
external_add:
    # rdi = a, rsi = b (SysV ABI)
    mov %edi, %eax
    add %esi, %eax
    ret
