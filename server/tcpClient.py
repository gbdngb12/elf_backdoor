import socket
from concurrent.futures import thread
import threading

def send(sock) :
    try :
        while True:
            inputData = input()
            inputData.replace('\n','')
            sock.send(inputData.encode('utf-8'))
            if inputData == "exit" :
                sock.close()
                break
    except :
        print("Exception")
        return

def recv(sock) :
    try:
        while True :
            data = sock.recv(65565)
            if len(data) == 0 :
                break
            print("received data: {}({}) bytes from {}".format(data.decode('utf-8'),len(data),address))
    except:
        print("Exception")
        return



host = "127.0.0.1"
port = 3490

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP)
#TCP 소켓 객체 생성

sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
#소켓객체 종료후 해당 포트 번호 재사용

sock.connect((host, port))


sock.send('whoami\n'.encode('utf-8'))

data = sock.recv(1024)
print(data)

#t1 = threading.Thread(target=send, args=(sock,), daemon=True)
#t1.start()
#
#t2 = threading.Thread(target=recv, args=(sock,), daemon=True)
#t2.start()
#
#
#t1.join()
#t2.join()
#