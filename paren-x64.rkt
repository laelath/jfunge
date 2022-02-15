#lang racket

(provide register?
         wrap-runtime
         generate-x64)

(define (wrap-runtime p)
  (string-append
   "global _start\n\nsection .text\n_start:\n"
   p))

(define (generate-x64 p)
  (string-append*
   (map ins->str p)))

(define (register? s)
  (and (symbol? s)
       (set-member? '(rax rbx rcx rdx rsi rdi rsp rbp r8 r9 r10 r11 r12 r13 r14 r15) s)))

(define (register->byte-reg r)
  (match r
    ['rax 'al]
    ['rbx 'bl]
    ['rcx 'cl]
    ['rdx 'dl]
    ['rsi 'sil]
    ['rdi 'dil]
    ['rsp 'spl]
    ['rbp 'bpl]
    ['r8 'r8b]
    ['r9 'r9b]
    ['r10 'r10b]
    ['r11 'r11b]
    ['r12 'r12b]
    ['r13 'r13b]
    ['r14 'r14b]
    ['r15 'r15b]))

;; TODO: verify range
(define (imm? s)
  (exact-integer? s))

(define (ins->str ins)
  (match ins
    [`(label ,lbl) (format "~a:~n" lbl)]
    [`(align ,(? imm? i)) (format "align ~a~n" i)]
    [`(nop) (format "  nop~n")]
    [`(mov byte ,d ,(? register? reg))
     (format "  mov ~a, ~a~n" (loc->str d) (register->byte-reg reg))]
    [`(mov ,d ,s) (bop->str 'mov d s)]
    [`(movzx ,d byte [,(? register? reg) + ,(? imm? i)])
     (format "  movzx ~a, BYTE [~a + ~a]~n" (loc->str d) reg i)]
    [`(lea ,d ,s) (bop->str 'lea d s)]
    [`(neg ,d) (format "  neg ~a~n" (loc->str d))]
    [`(add ,d ,s) (bop->str 'add d s)]
    [`(sub ,d ,s) (bop->str 'sub d s)]
    [`(imul ,d ,s) (bop->str 'imul d s)]
    [`(div ,s) (format "  div ~a~n" (src->str s))]
    [`(idiv ,s) (format "  idiv ~a~n" (src->str s))]
    [`(shl ,d ,s) (bop->str 'shl d s)]
    [`(shr ,d ,s) (bop->str 'shr d s)]
    [`(xor ,d ,s) (bop->str 'xor d s)]
    [`(or ,d ,s) (bop->str 'or d s)]
    [`(cmp ,d ,s) (bop->str 'cmp d s)]
    [`(test ,d ,s) (bop->str 'test d s)]
    [`(push ,s) (format "  push ~a~n" (src->str s))]
    [`(pop ,d) (format "  pop ~a~n" (loc->str d))]
    [`(call ,s) (format "  call ~a~n" (src->str s))]
    [`(ret) (format "  ret~n")]
    [`(jmp ,s) (format "  jmp ~a~n" (src->str s))]
    [`(je ,s) (format "  je ~a~n" (src->str s))]
    [`(jne ,s) (format "  jne ~a~n" (src->str s))]
    [`(jg ,s) (format "  jg ~a~n" (src->str s))]
    [`(jae ,s) (format "  jae ~a~n" (src->str s))]
    [`(jmp rel ,(? imm? i)) (format "  jmp $+~a~n" i)]
    [`(cmove ,d ,s) (bop->str 'cmove d s)]
    [`(cmovne ,d ,s) (bop->str 'cmovne d s)]
    [`(cmovg ,d ,s) (bop->str 'cmovg d s)]
    [`(syscall) (format "  syscall~n")]
    [_ (error (format "Unknown instruction: ~a" ins))]))

(define (bop->str ins d s)
  (format "  ~a ~a, ~a~n"
          ins
          (loc->str d)
          (src->str s)))

(define (src->str s)
  (if (imm? s)
      s
      (loc->str s)))

(define (loc->str s)
  (match s
    [(? register? reg) symbol->string reg]
    [`(,(? register? reg)) (format "[~a]" reg)]
    [`(,(? symbol? l)) (format "[~a]" l)]
    [`(,(? register? reg) + ,(? imm? i)) (format "[~a + ~a]" reg i)]
    [`(,(? register? r1) + ,(? register? r2)) (format "[~a + ~a]" r1 r2)]
    [`(,(? register? r) + ,(? symbol? l)) (format "[~a + ~a]" r l)]
    [(? symbol? s) symbol->string s]))