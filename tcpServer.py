import socket

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

while True:
    parent.close()
    inputData = input()
    inputData.replace('\n','')
    
    if inputData == "close" :
        child.close()
    child.send(inputData.encode('utf-8'))
    
    data = child.recv(65565)
    
    #print('server(parent):',parent)
    #print('server(child):',child)
    print("received data: {}({}) bytes from {}".format(data,len(data),address))

    