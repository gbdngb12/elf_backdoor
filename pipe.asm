BITS 64

%include "inc64.inc"

;; sys/syscall.h
%define SYS_write	1
%define SYS_mmap	9
%define SYS_clone	56
%define SYS_exit	60

;; unistd.h
%define STDIN		0
%define STDOUT		1
%define STDERR		2

;; sched.h
%define CLONE_VM	0x00000100
%define CLONE_FS	0x00000200
%define CLONE_FILES	0x00000400
%define CLONE_SIGHAND	0x00000800
%define CLONE_PARENT	0x00008000
%define CLONE_THREAD	0x00010000
%define CLONE_IO	0x80000000

;; sys/mman.h
%define MAP_GROWSDOWN	0x0100
%define MAP_ANONYMOUS	0x0020
%define MAP_PRIVATE	0x0002
%define PROT_READ	0x1
%define PROT_WRITE	0x2
%define PROT_EXEC	0x4

%define THREAD_FLAGS \
 CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_PARENT|CLONE_THREAD|CLONE_IO

;%define STACK_SIZE	(4096 * 1024)
%define STACK_SIZE	(100 * 4)

section .text
    global _start

_start:
    push rbp
    mov rbp, rsp
    sub rsp, 0x111 ; 148 byte Stack

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
    cmp eax, -1
    je _exit



    ;ssize_t write(int fd, const void *buf, size_t count);
    ;
    ; Return Value :
    ; On success, the number of bytes written is returned.  On error,
    ; -1 is returned, and errno is set to indicate the error.
    ;mov edi, STDOUT_FILENO ;stdout -> pipe
    ;lea rsi, testString
    ;mov rdx, 12
    ;mov rax, SYS_WRITE
    ;syscall
    ;cmp eax, -1
    ;je _writeFailed

_exit:
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


    ;mov edi, dword[rbp + fd1.write]
    ;mov rsi, lscommand
    ;mov rdx, 4
    ;mov rax, SYS_WRITE
    ;syscall
    ;running a thread
    mov rdi, _threadRead
    call thread_create
    mov rdi, _threadInput
    call thread_create
_mainThread:
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
    cmp eax, 0xfffffff2
    jne _mainThread
    exit


_threadInput: ;Input Thread
    ;
    ; ssize_t read(int fd, void *buf, size_t count);
    ;
    mov rdi, STDIN_FILENO
    lea rsi, [rbp + buffer.buf]
    mov rdx, 99
    mov rax, SYS_READ
    syscall
    cmp eax, -1
    je _readFailed
    mov dword[rbp + buffer.len], eax


    mov edi, dword[rbp + fd1.write]
    lea rsi, [rbp + buffer.buf]
    mov edx, dword[rbp + buffer.len] ;count
    mov rax, SYS_WRITE
    syscall

    cmp eax, 0
    jl _writeFailed
    ;exit String Check Routine
    lea rax, [rbp + buffer.buf] ; rax = &buf
    mov rcx, -1 ; index
_strcheck:
    add rcx, 1
    cmp rcx, exitlen
    je _closeRoutine
    mov al, byte[rbp + buffer.buf + rcx] ; buf[rcx]
    mov dl, byte[exitString + rcx] ; "e", "x", "i", "t", "\n"
    cmp al, dl
    je _strcheck
    jmp _threadInput ;Input Thread

_closeRoutine:
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
    
    mov rsp, rbp
    pop rbp
    exit




_threadWrite:
    ;ssize_t write(int fd, const void *buf, size_t count);
    ;
    ; Return Value :
    ; On success, the number of bytes written is returned.  On error,
    ; -1 is returned, and errno is set to indicate the error.
    mov rdi, STDOUT_FILENO
    lea rsi, [rbp + c.char]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
    cmp eax, 0
    jl _writeFailed
_threadRead:
    ; thread Read
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
    lea rsi, [rbp + c.char]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    cmp eax, 0
    jl _readFailed  
    ja _threadWrite
    je _threadRead




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


; Data Structure
struc fd1, -0x8 ;8 Last Size + Current Size
    .read:    resb 4  ;4bytes
    .write:   resb 4  ;4bytes
endstruc

struc fd2, -0x10 ;16 Last Size + Current Size
    .read:  resb 4 ;4bytes
    .write: resb 4 ;4bytes
endstruc

struc pid, -0x14 ;20 Last Size + Current Size
    .pid:   resb 4 ;4bytes
endstruc

struc siginfo_t, -0x94 ;148 Last Size + Current Size
    .siginfo: resb 128 ; 128bytes
endstruc

struc buffer, -0xfc; 248 Last Size + Current Size
    .buf: resb 100 ; 100bytes
    .len: resb 4 ;4bytes
endstruc

struc newargv, -0x10c;264 Last Size + Current Size
    .sh: resb 8   ;8bytes
    .null: resb 8 ;8bytes
endstruc

struc newenviron, -0x114;272 Last Size + Current Size
    .null: resb 8 ;8bytes
endstruc

struc c, -0x115
    .char: resb 1;1bytes
endstruc

; Error Handling Routine
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

_writeFailed:
    print writeError
    mov rsp, rbp
    pop rbp
    exit

_closeFailed:
    print closeError
    mov rsp, rbp
    pop rbp
    exit

_readFailed:
    print readError
    mov rsp, rbp
    pop rbp
    exit

_killFailed:
    print killError
    mov rsp, rbp
    pop rbp
    exit



; Error Message
closeError: db"close Error",33,10,0
pipeError: db "pipe Error",33,10,0
forkError: db "fork Error",33,10,0
waitidError: db "waitid Error",33,10,0
dup2Error: db "dup Error",33,10,0
writeError: db "write Error",33,10,0
readError: db "read Error",33,10,0
testString: db "test String",0
killError: db "kill Error",33,10,0
binsh: db "/bin/sh",0
; Close String
exitString: db "exit",10
exitlen equ 5

P_PID equ 1
