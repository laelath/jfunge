#!/bin/bash

mkdir -p target
racket -t jfunge.rkt -m $1 > target/program.asm
nasm -o target/program.o -f elf64 target/program.asm
ld -N -o target/program target/program.o

./target/program
