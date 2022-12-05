# Simple-elf-backdoor

It is an elf backdoor written in pure assembly language.

# Current Status(2022/12/04)

The backdoor and server have been completed, but code modifications for elf-injection are underway.

# Expected Behavior upon completion
## Attacker
### backdoor
```bash
$ nasm -f bin backdoor.s -o backdoor.bin
$ ./elfinject elftarget backdoor.bin ".injected" 0x800000 0
```
### server
```
$ python3 tcpServer.py
```
## victim
If victim download or obtain the file in any way
```
$ ./elftarget
```
The victim uses the original program without problems and Attackers use backdoors.

### Current development before elfinjection
