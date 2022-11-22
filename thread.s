;; Pure assembly, library-free Linux threading demo
bits 64
global _start

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

%define MAX_LINES	1000000	; number of output lines before exiting

section .data
count:	dq MAX_LINES

section .text
_start:
	; Spawn a few threads
	mov rdi, threadfn
	call thread_create
	mov rdi, threadfn
	call thread_create

.loop:	call check_count
	mov rdi, .hello
	call puts
	mov rdi, 0
	jmp .loop

.hello:	db `Hello from \e[93;1mmain\e[0m!\n\0`

;; void threadfn(void)
threadfn:
	call check_count
	mov rdi, .hello
	call puts
	jmp threadfn
.hello:	db `Hello from \e[91;1mthread\e[0m!\n\0`

;; void check_count(void) -- may not return
check_count:
	mov rax, -1
	lock xadd [count], rax ; mutex lock
	jl .exit
	ret
.exit	mov rdi, 0
	mov rax, SYS_exit
	syscall

;; void puts(char *)
puts:
	mov rsi, rdi
	mov rdx, -1
.count:	inc rdx
	cmp byte [rsi + rdx], 0
	jne .count
	mov rdi, STDOUT
	mov rax, SYS_write
	syscall
	ret

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