#!/bin/bash

mkdir -p target
racket -t jfunge.rkt -m $1 > target/program.asm
nasm -o target/program.o -f macho64 target/program.asm
./ld64.py target/program.o -o target/program \
-segprot __TEXT rwx rwx -macosx_version_min 10.7 &>/dev/null # i dont care if 10.7 is deprecated damnit

./target/program