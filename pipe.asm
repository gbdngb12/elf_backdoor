BITS 64

%include "inc64.inc"

section .text
    global _start

_start:
    push rbp
    mov rbp, rsp


    mov rsp, rbp
    pop rbp
    exit