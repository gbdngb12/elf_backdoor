BITS 64

%include "inc64.inc"
%include "thread.inc"

section .text
    global _start

_start:
    push rbp
    mov rbp, rsp
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
    jle _sockFailed
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
    jle _connectFailed


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
    mov byte[rbp + socket.buf + rax ], 10 ; buf[numbytes] = '\n';

    ;exit String Check Routine
    lea rax, [rbp + socket.buf] ; rax = &buf
    mov rcx, -1 ; index
_strcheck:
    add rcx, 1
    cmp rcx, exitlen
    je _exit
    mov al, byte[rbp + socket.buf + rcx] ; buf[rcx]
    mov dl, byte[exitString + rcx] ; "e", "x", "i", "t", "\n"
    cmp al, dl
    je _strcheck



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


;--------------------------------Thread---------------------------------------------
;; long thread_create(void (*)(void))
thread_create:
    ;                          $rdi             $rsi           
	; long clone(unsigned long flags, void *child_stack,
	;			  $rdx        $r10					$r8
    ;       void *ptid, void *ctid, struct pt_regs *regs);
	; pointer is always indicate Low Address
    ;  ┌────────────────┐            
	;  │ 32	 33	 34	 35 │
	;  │ 28	 29	 30	 31 │
	;  │ 24	 25	 26	 27 │
	;  │ 20	 21	 22	 23 │
	;  │ 16	 17	 18	 19 │
	;  │ 12	 13	 14	 15 │
	;  │ 8   9	 10	 11 │
	;  │ 4   5   6   7  │
	;  │ 0 	 1	 2	 3  │
	;  └────────────────┘
	;
	;				 
	;            				 ┌────────────────┐						       
	;         Main Thread rsp--> │    original    │	                           Main Thread ret -> original return Address
	;      	  					 │ return Address │			
	;      		 				 ┈ ┈ ┈ ┈ ┈ ┈ ┈ 						      
	;            				 │    thread_fn   │          sys_clone()  
	;            				 │     Address    │                       
	;      		 				 ┈ ┈ ┈ ┈ ┈ ┈ ┈ 						     
	;    		 				 │................│                     
	;         New Thread rsp-->  │    thread_fn   │						      New Thread ret -> thread_fn Address
	;     Stack Size = 12        │     Address    │		 				 
	; $rax(End Point Address)--> │ 8   9   10  11 │					     
	;         				     │ 4   5   6   7  │                      
	;         				     │ 0   1   2   3  │                      
	;         				     └────────────────┘                            

	push rdi ;thread_fn
	call stack_create
	lea rsi, [rax + STACK_SIZE - 8] ;thread function Pointer
	pop qword [rsi] ; thread function Pointer->thread_fn
	mov rdi, THREAD_FLAGS ; flags
	mov rax, SYS_clone
	syscall ;여기서 thread 생성되며 실행이 계속됨
	ret

;; void *stack_create(void)
stack_create:
    ;                  $rdi          $rsi       $rdx      $r10
    ; void *mmap(void *addr, size_t length, int prot, int flags,
    ;                  $r8          $r9
    ;              int fd, off_t offset);
    ; Return Value:
    ; On success, mmap() returns a pointer to the mapped area.  On
    ;   error, the value MAP_FAILED (that is, (void *) -1) is returned,
    ;   and errno is set to indicate the error.
	mov rdi, 0
	mov rsi, STACK_SIZE
	mov rdx, PROT_WRITE | PROT_READ
	mov r10, MAP_ANONYMOUS | MAP_PRIVATE | MAP_GROWSDOWN
	mov r8, -1
	mov r9, 0
	mov rax, SYS_mmap
	syscall
	ret
;--------------------------------Thread---------------------------------------------



;--------------------------------Data Structure-------------------------------------

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

struc fd1, -0x16c ;364 Last Size + Current Size
    .read: resb 4 ;4bytes
    .write: resb 4 ;4bytes
endstruc

struc fd2, -0x174 ;372 Last Size + Current Size
    .read: resb 4 ;4bytes
    .write: resb 4 ;4bytes
endstruc

struc newargv, -0x184 ; 388 Last Size + Current Size
    .sh: resb   8 ;8bytes
    .null: resb 8 ;8bytes
endstruc

struc newenviron, -0x18c ; 396 Last Size + Current Size
    .null resb 8 ;8bytes
endstruc

struc c, -0x18d ; 397 Last Size + Current Size
    .char: resb 1 ;1bytes
endstruc

;--------------------------------Data Structure-------------------------------------


;--------------------------------Error Handling Routine-----------------------------
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


;--------------------------------Error Handling Routine-----------------------------


;sh
binsh: db "/bin/sh",0

; buffer SIze
MAXDATASIZE equ 100

; For socket
SOCK_STREAM equ 1
AF_INET equ 2
AF_INET equ 2

; exit String
exitString: db "exit",10
exitlen equ 5