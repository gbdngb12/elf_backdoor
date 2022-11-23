import socket
from concurrent.futures import thread
import threading


host = "127.0.0.1"
port = 3490

parent = socket.socket(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP)
#TCP 소켓 객체 생성

parent.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
#소켓객체 종료후 해당 포트 번호 재사용

parent.bind((host,port))

parent.listen(10)
#3단계 연결 설정에 따라 동작하는 TCP 클라이언트10대로부터 연결 요청을 기다린다.(최대 10대 TCP 클라이언트 접속가능)

(child, address) = parent.accept() #parent process에서 기다리다가 받으면 child process에 socket객체와 address에 넘김
#child.settimeout(10.0)

while True:
    parent.close()
    
    data = child.recv(65565) # do Thread!

    inputData = input()
    inputData.replace('\n','')
    
    child.send(inputData.encode('utf-8'))
    if inputData == "exit" :
        child.close()
        exit(0)
    

    print("received data: {}({}) bytes from {}".format(data.decode('utf-8'),len(data),address))