BITS 64

%include "inc64.inc"

section .text
    global _start

_start:
    push rbp
    mov rbp, rsp
    sub rsp, 0x110 ; 148 byte Stack

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


    mov edi, dword[rbp + fd1.write]
    mov rsi, lscommand
    mov rdx, 4
    mov rax, SYS_WRITE
    syscall
    jmp _threadRead


    
_threadWrite:
    ;ssize_t write(int fd, const void *buf, size_t count);
    ;
    ; Return Value :
    ; On success, the number of bytes written is returned.  On error,
    ; -1 is returned, and errno is set to indicate the error.
    mov rdi, STDOUT_FILENO
    lea rsi, [rbp + buffer.buf]
    mov rdx, 1
    mov rax, SYS_WRITE
    syscall
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
    lea rsi, [rbp + buffer.buf]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    cmp eax, 0
    ja _threadWrite
    je _threadRead
    jl _readFailed  
    
    
    
    
    ; input!

    

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

    ;                       $rdi     $rsi            $rdx         $r10
    ; int waitid(idtype_t idtype, id_t id, siginfo_t *infop, int options);
    ;
    ; Return Value:
    ; waitid():  returns 0 on success or if WNOHANG was specified and 
    ; no child(ren) specified by id has yet changed state; on error, -1 is returned.
    mov edi, P_PID
    mov esi, dword[rbp + pid.pid]
    lea rdx, [siginfo_t.siginfo]
    mov r10, 6 ;WEXITED|WSTOPPED
    mov rax, SYS_WAITID
    syscall
    cmp eax, -1
    je _waitidFailed

    mov rsp, rbp
    pop rbp
    exit


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

struc buffer, -0xf8; 248 Last Size + Current Size
    .buf: resb 100 ; 100bytes
endstruc

struc newargv, 0x108;264 Last Size + Current Size
    .sh: resb 8   ;8bytes
    .null: resb 8 ;8bytes
endstruc

struc newenviron, 0x110;272 Last Size + Current Size
    .null: resb 8 ;8bytes
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

; Error Message
closeError: db"close Error",33,10,0
pipeError: db "pipe Error",33,10,0
forkError: db "fork Error",33,10,0
waitidError: db "waitid Error",33,10,0
dup2Error: db "dup Error",33,10,0
writeError: db "write Error",33,10,0
readError: db "read Error",33,10,0
testString: db "test String",0
binsh: db "/bin/sh",0
lscommand: db "ls",0,10
P_PID equ 1
