# JFunge

JFunge is a Befunge to x86_64 compiler with support for `g` and `p`.

## Installation and Usage

To install, just clone the repository.
The output of the compiler is NASM-compatible assembly, and so requires NASM to
create an executable from the output.
To compile a program, run the following commands:
```
racket -t jfunge.rkt -m foo.bf > foo.s
nasm -f elf64 foo.s
ld -o foo foo.o
```
Yes this is clunky, I will automate these steps later.
