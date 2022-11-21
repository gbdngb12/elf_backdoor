#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    int fd1[2], fd2[2];
    pid_t pid;
    char buf;
    int len, status;

    // 파이프를 하나 생성한다. 생성된 파일 기술자 fd1은 부모 프로세스에서
    // 자식 프로세스로 데이터를 보낼때 사용한다.
    if (pipe(fd1) == -1) {
        perror("pipe");
        exit(1);
    }

    // 또 다른 파이프를 생성한다. 파일 기술자 fd2는 자식 프로세스에서
    // 부모 프로세스로 데이터를 보낼때 사용한다.
    if (pipe(fd2) == -1) {
        perror("pipe");
        exit(1);
    }

    switch (pid = fork()) {
        case -1:
            perror("fork");
            exit(1);
            break;
        // 자식 프로세스는 부모 프로세스에서 오는 데이터를 읽는 데 사용할
        // fd1[0]을 남겨두고 fd1[1]을 닫느다. 또한 부모 프로세스로 데이터를 보내는데
        // 사용할 fd2[1]을 남겨두고 fd2[0]을 닫느다.
        case 0: /* child */
            close(fd1[1]);
            close(fd2[0]);

            if (fd2[1] != STDOUT_FILENO) {  //표준출력 -> fd2[1](write)
                dup2(fd2[1], STDOUT_FILENO);
                close(fd2[1]);
            }

            if (fd1[0] != STDIN_FILENO) {  //표준입력 -> fd1[0](read)
                dup2(fd1[0], STDIN_FILENO);
                close(fd1[0]);
            }

            char *newargv[] = {"/bin/sh", NULL};
            char *newenviron[] = {NULL};
            if (execve("/bin/sh", newargv, newenviron) == -1) {
                perror("execve");
                exit(1);
            }
            break;
        // 부모 프로세스는 자식 프로세스와 반대다. 자식 프로세스에 데이터를 보내는데 사용할 fd[1]을
        // 남겨두고, 자식 프로세스에서 오는 데이터를 읽는 데 사용할 fd2[0]을 남겨둔다.
        default:
            close(fd1[0]);
            close(fd2[1]);
            //얘는 thread로 실행
            while(read(fd2[0], &buf, 1) > 0) { //자식 프로세스로부터 결과를 읽어온다.
                write(STDOUT_FILENO, &buf, 1);
            }
            while(1) {
                char input[100] = { 0 };
                if(read(STDIN_FILENO, input,100) == -1) {
                    perror("read");
                }

                write(fd1[1], input, strlen(input));  // 부모프로세스가 자식 프로세스에게
                // sleep(2);
                
            }

            close(fd1[1]);
            close(fd2[0]);
            waitpid(pid, &status, 0);
            break;
    }

    return 0;
}