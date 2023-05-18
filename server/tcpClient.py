import socket
from concurrent.futures import thread
import threading
import time

def send(sock) :
    try :
        while True:
            inputData = input()
            inputData += '\n'
            sock.send(inputData.encode('utf-8'))
            if inputData == "exit\n" :
                sock.close()
                break
    except Exception as e:
        print("Exception", str(e))
        return

def recv(sock) :
    try:
        while True :
            data = sock.recv(65565)
            if len(data) == 0 :
                break
            print(data.decode('utf-8'))
    except Exception as e:
        print("Exception", str(e))
        return


host = "127.0.0.1"
port = 3490

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP)
#TCP 소켓 객체 생성

sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
#소켓객체 종료후 해당 포트 번호 재사용


sock.connect((host, port))


t1 = threading.Thread(target=send, args=(sock,), daemon=True)
t1.start()

t2 = threading.Thread(target=recv, args=(sock,), daemon=True)
t2.start()


t1.join()
t2.join()

#while True :
#    inputData = input()
#    inputData += '\n'
#    #if inputData == "\n" :
#    #    continue
#    sock.send(inputData.encode('utf-8'))
#
#    if inputData == "exit\n" :
#        sock.close()
#        break
#
#    try :
#        data = sock.recv(1024)
#        print(data.decode('utf-8'))
#    except socket.timeout:
#        continue