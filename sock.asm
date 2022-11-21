BITS 64

%include "inc64.inc"

section .text
    global _start

;rax(syscall number), rdi, rsi, rdx, r10, r8, r9, Stack
_start:
    push rbp
    mov rbp, rsp
    sub rsp, 0x16c ; 364 byte Stack

    ;               $rdi       $rsi      $rdx
    ;int socket(int domain, int type, int protocol);
    ;   
    ; Return Value:
    ; On success, a file descriptor for the new socket is returned.  On
    ; error, -1 is returned, and errno is set to indicate the error.
    mov rdi, AF_INET ; int domain
    mov rsi, SOCK_STREAM ; int type
    mov rdx, 0 ; int protocol
    mov rax, SYS_SOCKET ; socket
    syscall ; socket(AF_INET, SOCK_STREAM, 0);
    
    ; if(socket == -1)
    cmp eax, -1
    je _sockFailed
    mov dword[rbp + socket.socketfd], eax

    ; their_addr.sin_family = AF_INET;   /* host byte order */
    ; their_addr.sin_port = htons(PORT); /* short, network byte order */
    ; their_addr.sin_addr = *((struct in_addr *)he->h_addr);
    ; bzero(&(their_addr.sin_zero), 8); /* zero the rest of the struct */
    mov word [rbp + sockaddr_in.sin_family], AF_INET ; host byte order
    mov word [rbp + sockaddr_in.sin_port], 0xa20d ; 3490 PORT
    mov dword [rbp + sockaddr_in.sin_addr], 0x100007f ; 127.0.0.1
    mov qword [rbp + sockaddr_in.sin_zero], 0


    ;                 $rdi                        $rsi               $rdx
    ;int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
    ;
    ; Return Value:
    ; If  the  connection or binding succeeds, zero is returned.  On error, -1 is
    ;   returned, and errno is set appropriately.
    mov edi, dword[rbp + socket.socketfd] ; int sockfd
    lea rsi, qword[rbp + sockaddr_in] ; const struct sockaddr *addr
    mov rdx, 0x10 ; sizeof(const struct sockaddr)
    mov rax, SYS_CONNECT ; connect
    syscall ; connect(sockfd, addr, 16);
    cmp eax, -1
    je _connectFailed

_loop:
    ;                      $rdi        $rsi        $rdx      $r10    
    ;ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
    ;                                     $r8                 $r9
    ;                   struct sockaddr *src_addr, socklen_t *addrlen);
    ; Return Value:
    ; These  calls  return  the number of bytes received, or -1 if an error occurred.  In the
    ;   event of an error, errno is set to indicate the error.
    ;   When a stream socket peer has performed an orderly shutdown, the return value will be 0
    ;   (the traditional "end-of-file" return).
    ;   Datagram  sockets in various domains (e.g., the UNIX and Internet domains) permit zero-
    ;   length datagrams.  When such a datagram is received, the return value is 0.
    ;   The value 0 may also be returned if the requested number of bytes  to  receive  from  a
    ;   stream socket was 0.
    mov edi, dword[rbp + socket.socketfd] ; sockfd
    lea rsi, dword[rbp + socket.buf] ; buf
    mov rdx, MAXDATASIZE ; len
    mov r10, 0 ; flags
    mov r8, 0 ; NULL
    mov r9, 0 ; NULL
    mov rax, SYS_RECVFROM ; recvfrom
    syscall ; recvfrom(sockfd, buf, 100, 0, 0, 0);

    cmp eax, 0
    jl _recvfromFailed
    je _exit; shutdown or received from stream socket was 0

    mov dword[rbp + socket.len], eax ; save to length
    mov byte[rbp + socket.buf + rax ], 0 ; buf[numbytes] = '\0';

    ;close String Check Routine
    lea rax, [rbp + socket.buf] ; rax = &buf
    mov rcx, -1 ; index
_strcheck:
    add rcx, 1
    cmp rcx, closelen
    je _exit
    mov al, byte[rbp + socket.buf + rcx] ; buf[rcx]
    mov dl, byte[closeString + rcx] ; "c", "l", "o", "s", "e", "\0"
    cmp al, dl
    je _strcheck

    ;
    ; shell command
    ;


    ;                   $rdi               $rsi         $rdx      $r10
    ;ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
    ;                                           $r8                    $r9
    ;                  const struct sockaddr *dest_addr, socklen_t addrlen);
    ; Return Value:
    ; On success, these calls return the number of bytes sent.  
    ; On error, -1 is returned, and errno is set appropriately.
    mov edi, dword[rbp + socket.socketfd] ; sockfd
    lea rsi, [rbp + socket.buf] ; buf
    mov edx, dword[rbp + socket.len] ; len
    add edx, 1 ; + '\0'
    mov r10, 0 ;
    mov r8, 0 ;
    mov r9, 0 ; because it is already connected
    mov rax, SYS_SENDTO
    syscall
    cmp eax, -1
    je _sendtoFailed

    jmp _loop

_exit:
    ;              $rdi
    ; int close(int fd);
    ; Return Value:
    ; close() returns zero on success.  On error, -1 is returned, 
    ; and errno is set appropriately.
    mov edi, dword[rbp + socket.socketfd] ; sockfd
    mov rax, SYS_CLOSE
    syscall
    cmp eax, -1
    je _closeFailed
    mov rsp, rbp
    pop rbp
    exit


; Constant Number
; For buffer Size
MAXDATASIZE equ 100

; For socket
SOCK_STREAM equ 1
AF_INET equ 2
AF_INET equ 2

; Data Structure
struc sockaddr_in, -0x10 ;16 Last Size + Current Size
    .sin_family:    resb 2  ;2bytes
    .sin_port:      resb 2  ;2bytes
    .sin_addr:      resb 4  ;4bytes
    .sin_zero:      resb 8  ;8bytes
endstruc

struc pid, -0x14 ;20 Last Size + Current Size
    .pid resb 4 ;4bytes
endstruc

struc socket, -0x80 ;128 Last Size + Current Size
    .socketfd:       resb 4 ;4bytes
    .len:            resb 4 ;4btres
    .buf:            resb MAXDATASIZE ;100bytes buf
endstruc

struc commandOutput, -0xe4 ;228 Last Size + Current Size
    .commandOutput:  resb MAXDATASIZE ;100bytes commandOutput
endstruc

struc siginfo_t, -0x164 ;356 Last Size + Current Size
    .siginfo: resb 128 ; 128bytes
endstruc

struc pipefd, -0x16c ;364 Last Size + Current Size
    .read: resb 4 ;4bytes
    .write: resb 4 ;4bytes
endstruc


; Error Handling Routine
_sockFailed:
    print socketError
    mov rsp, rbp
    pop rbp
    exit
_closeFailed:
    print closeError
    mov rsp, rbp
    pop rbp
    exit
_connectFailed:
    print connectError
    mov rsp, rbp
    pop rbp
    exit
_recvfromFailed:
    print recvfromError
    mov rsp, rbp
    pop rbp
    exit
_sendtoFailed:
    print sendtoError
    mov rsp, rbp
    pop rbp
    exit
_pipeFailed:
    print pipeError
    mov rsp, rbp
    pop rbp
    exit
_forkFailed:
    print forkError
    mov rsp, rbp
    pop rbp
    exit
_waitidFailed:
    print waitidError
    mov rsp, rbp
    pop rbp
    exit
_dup2Failed:
    print dup2Error
    mov rsp, rbp
    pop rbp
    exit

; Error Message
socketError: db "Socket Error",33,10,0
closeError: db "close Error",33,10,0
connectError: db "connect Error",33,10,0
recvfromError: db "recvfrom Error",33,10,0
sendtoError: db "sendto Error",33,10,0
pipeError: db "pipe Error",33,10,0
forkError: db "fork Error",33,10,0
waitidError: db "waitid Error",33,10,0
dup2Error: db "dup Error",33,10,0

; Close String
closeString: db "close",0
closelen equ 6