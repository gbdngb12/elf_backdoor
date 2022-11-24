BITS 64
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

;waitid
P_PID equ 1