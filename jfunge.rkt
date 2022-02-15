#lang racket

(require "paren-x64.rkt")

(provide main)

;; rsp: stack pointer
;; rbp: location of the bottom of the stack
;; r12: grid width in cells
;; r13: grid height in cells
;; r14: jump offset
;; r15: address at start of cell

;; the start of the program loads the location of the first cell into r15 and jumps to it.
;; from then on cells update r15 to the location of the next cell and jump

;; the value of rbp is saved when the program starts
;; then 0 is pushed onto the stack.
;; then stack pops check if rsp has made it back to the base
;; and bumps it back if it has reached the bottom.
;; (mov rbp rsp)
;; (push 0)

;; +--------+ -+     -+
;; | Quote  |  | (1)  |
;; | Ramp   |  |      |
;; +--------+ -+      | (2)
;; | Body   |         |
;; | Ramp   |         |
;; +--------+        -+

;; (1) quote section, this contains the code that pushes the ascii value onto the stack
;; (2) cell-size

;; Ramp is the bit of code that launches execution on to the next cell

(define cell-size 64)
(define cell-shift 6)
(define ramp-size 6)
(define quote-size (+ 4 ramp-size))

(define (main fn)
  (with-input-from-file fn
    (λ ()
      (let ([p (port->string)])
        (display (compile p))))))

(define (compile p)
  (wrap-runtime (generate-x64 (create-grid p))))

(define (create-grid p)
  (let* ([lines (string-split p "\n")]
         [width (apply max (map string-length lines))]
         [height (length lines)])
    `(;; initialize rbp and stack base value
      (mov rbp rsp)
      (push 0)
      ;; store grid width and height
      (mov r12 ,width)
      (mov r13 ,height)
      ;; default to left-to-right control flow
      (mov r14 ,cell-size)
      ;; start execution
      (mov r15 _grid_start)
      (mov rax ,(+ (* (+ width 2) cell-size) quote-size))
      (add r15 rax)
      (jmp r15)

      ;; function definitions
      ,@get-cell
      ,@put-cell
      ,@random-dir
      ,@write-num

      ;; cell table for cell puts
      (align ,cell-size)
      (label _cell_table)
      ,@(append* (build-list 128 (λ (n) (create-cell (integer->char n)))))

      ;; bit of a hack to get the start of the grid
      (align 64)
      (label _grid_start)

      ;; grid
      ,@(append* (make-list width top-cell))
      ,@corner-cell
      ,@(append-map
         (λ (l)
           `(,@left-cell
             ,@(append-map create-cell (string->list l))
             ,@(append* (make-list (- width (string-length l)) (create-cell #\space)))
             ,@right-cell))
         lines)
      ,@corner-cell
      ,@(append* (make-list width bot-cell)))))

;; returns 0 when given x,y is out of bounds
;; TODO: return #\space when resizing is implemented
;; rdi: y
;; rsi: x
(define get-cell
  `((label get_cell)

    (cmp rdi r13) ; compare y to height
    (jae .get_cell_oob)
    (cmp rsi r12) ; compare x to width
    (jae .get_cell_oob)

    (mov rax r12)
    (add rax 2)
    (imul rax rdi)
    (add rsi r12)
    (add rsi 2)
    (add rax rsi) ; rax has y * (width + 2) + width + x + 2
    (shl rax ,cell-shift)
    (mov rbx _grid_start)
    (add rax rbx)
    (movzx rax byte [rax + 1])
    (mov rbx ,(char->integer #\"))
    (test rax #x80) ; if this bit is set, we read from a quote
    (cmovne rax rbx)
    (ret)

    (label .get_cell_oob)
    (mov rax ,(char->integer #\null))
    (ret)))

;; Silently ignores both oob and non-ascii puts
;; TODO: resize board on oob put (v. hard)
;; TODO: error-exit on non-ascii write
;; rdi: y
;; rsi: x
;; rdx: char
;; does not return since this cell may have been overwritten
(define put-cell
  `((label put_cell)

    (cmp rdx #x7F)
    (jae .put_cell_invalid)

    (cmp rdi r13) ; compare y to height
    (jae .put_cell_oob)
    (cmp rsi r12) ; compare x to width
    (jae .put_cell_oob)

    (mov rax r12)
    (add rax 2)
    (imul rax rdi)
    (add rsi r12)
    (add rsi 2)
    (add rax rsi) ; rax has y * (width + 2) + width + x + 2
    (shl rax ,cell-shift)
    (mov rbx _grid_start)
    (add rax rbx)

    (shl rdx ,cell-shift)
    (mov rbx _cell_table)
    (add rdx rbx) ; rdx has pointer to new cell data

    ;; copy data from cell table to the grid
    ,@(append*
       (build-list (/ cell-size 8)
                   (λ (n)
                     `((mov rbx [rdx + ,(* 8 n)])
                       (mov [rax + ,(* 8 n)] rbx)))))
    
    (add r15 r14)
    (jmp r15)

    (label .put_cell_invalid)
    (label .put_cell_oob)
    (add r15 r14)
    (jmp r15)))

;; moves a random, valid direction into r14
(define random-dir
  `((label rand_dir)
    (mov rax 318) ; sys_getrandom
    (push 0)      ; allocate space on stack
    (mov rdi rsp) ; top of stack
    (mov rsi 1)   ; one byte of randomness
    (xor rdx rdx) ; clear flags
    (syscall)
    (pop rax)
    (test rax 2)
    (jne .rand_vert)
    
    (mov r14 ,cell-size)
    (mov rbx r14)
    (neg rbx)
    (test rax 1)
    (cmovne r14 rbx)
    (ret)
    
    (label .rand_vert)
    (mov r14 r12)
    (add r14 2)
    (shl r14 ,cell-shift)
    (mov rbx r14)
    (neg rbx)
    (test rax 1)
    (cmovne r14 rbx)
    (ret)))

;; rdi: number to write
(define write-num
  `((label write_num)

    (cmp rdi 0)
    (je .write_num_zero)
    (jg .write_num_pos)

    (push rdi)
    (push ,(char->integer #\-))
    (mov rax 1)
    (mov rdi 1)
    (mov rsi rsp)
    (mov rdx 1)
    (syscall)
    (pop rax)
    (pop rdi)
    (neg rdi)

    (label .write_num_pos)
    (sub rsp 24)
    (mov rax rdi)
    (mov rbx 24)
    (mov rcx 10)
    (label .write_num_loop)
    (xor rdx rdx)
    (div rcx)
    (add rdx ,(char->integer #\0))
    (sub rbx 1)
    (mov byte [rsp + rbx] rdx)
    (cmp rax 0)
    (jne .write_num_loop)

    (mov rax 1)   ; sys_write
    (mov rdi 1)   ; stdout
    (mov rsi rsp)
    (add rsi rbx) ; pointing to location of rbx on stack
    (mov rdx 24)
    (sub rdx rbx) ; length of num
    (syscall)

    (add rsp 24)
    (ret)

    (label .write_num_zero)
    (push ,(char->integer #\0))
    (mov rax 1)   ; sys_write
    (mov rdi 1)   ; stdout
    (mov rsi rsp) ; top of stack
    (mov rdx 1)   ; one byte
    (syscall)
    (pop rax)
    (ret)))

(define top-cell
  `((align ,cell-size)
    ;; quote and bridge slide down nops
    ,@(make-list 10 '(nop))
    ;; regular entry
    (mov rax r12)         ; 3
    (add rax 2)           ; 4
    (imul rax r13)        ; 4
    (shl rax ,cell-shift) ; 4
    (add r15 rax)         ; 3
    (jmp r15)))           ; 3

(define bot-cell
  `((align ,cell-size)
    ;; quote and bridge slide down nops
    ,@(make-list 10 '(nop))
    ;; regular entry
    (mov rax r12)
    (add rax 2)
    (imul rax r13)
    (shl rax ,cell-shift)
    (sub r15 rax)
    (jmp r15)))

(define left-cell
  `((align ,cell-size)
    ;; quote and bridge slide down nops
    ,@(make-list 10 '(nop))
    ;; regular entry
    (mov rax r12)
    (shl rax ,cell-shift)
    (add r15 rax)
    (jmp r15)))

(define right-cell
  `((align ,cell-size)
    ;; quote and bridge slide down nops
    ,@(make-list 10 '(nop))
    ;; regular entry
    (mov rax r12)
    (shl rax ,cell-shift)
    (sub r15 rax)
    (jmp r15)))

;; a single nop to make the alignment go to the next one
(define corner-cell
  `((align ,cell-size)
    (nop)))

(define (create-cell c)
  (append `((align ,cell-size))
          (cell-quote c)
          cell-ramp
          (cell-body c)
          cell-ramp))

(define cell-ramp
  `((add r15 r14)
    (jmp r15)))

;; generates the quote mode of a cell with a given byte
(define (cell-quote c)
  (if (char=? c #\")
      `((add r15 ,quote-size))
      `((push ,(char->integer c))
        (nop)
        (nop))))

(define (cell-body c)
  (match c
    [(? (λ (d) (char<=? #\0 d #\9)) d)
     `((push ,(- (char->integer c) (char->integer #\0))))]
    [#\+ +-body]
    [#\- --body]
    [#\* *-body]
    [#\/ /-body]
    [#\% %-body]
    [#\! !-body]
    [#\` gt-body]
    [#\^ ^-body]
    [#\v v-body]
    [#\< <-body]
    [#\> >-body]
    [#\? ?-body]
    [#\_ _-body]
    [#\| bar-body]
    [#\" quote-body]
    [#\: :-body]
    [#\\ \-body]
    [#\$ $-body]
    [#\. .-body]
    [#\, comma-body]
    [#\# bridge-body]
    [#\p p-body]
    [#\g g-body]
    [#\& &-body]
    [#\~ ~-body]
    [#\@ @-body]
    [_ noop-body]))

(define (safe-pop reg)
  `((mov r11 rsp)
    (pop ,reg)
    (cmp rbp rsp)
    (cmove rsp r11)))

(define +-body
  `(,@(safe-pop 'rax)
    ,@(safe-pop 'rbx)
    (add rax rbx)
    (push rax)))

(define --body
  `(,@(safe-pop 'rax)
    ,@(safe-pop 'rbx)
    (sub rbx rax)
    (push rbx)))

(define *-body
  `(,@(safe-pop 'rax)
    ,@(safe-pop 'rbx)
    (imul rax rbx)
    (push rax)))

(define /-body
  `(,@(safe-pop 'rbx)
    ,@(safe-pop 'rax)
    (xor rdx rdx)
    (idiv rbx)
    (push rax)))

(define %-body
  `(,@(safe-pop 'rbx)
    ,@(safe-pop 'rax)
    (xor rdx rdx)
    (idiv rbx)
    (push rdx)))

(define !-body
  `(,@(safe-pop 'rax)
    (mov rbx 1)
    (xor rcx rcx)
    (cmp rax 0)
    (cmove rcx rbx)
    (push rcx)))

(define gt-body
  `(,@(safe-pop 'rax)
    ,@(safe-pop 'rbx)
    (xor rdx rdx)
    (mov rcx 1)
    (cmp rbx rax)
    (cmovg rdx rcx)
    (push rdx)))

(define ^-body
  `((mov r14 r12)
    (add r14 2)
    (shl r14 ,cell-shift)
    (neg r14)))

(define v-body
  `((mov r14 r12)
    (add r14 2)
    (shl r14 ,cell-shift)))

(define <-body
  `((mov r14 ,(- cell-size))))

(define >-body
  `((mov r14 ,cell-size)))

;; go in a random direction
(define ?-body
  `((mov rax rand_dir)
    (call rax)))

(define _-body
  `(,@(safe-pop 'rax)
    ,@<-body
    (mov rbx r14)
    (neg rbx)
    (cmp rax 0)
    (cmove r14 rbx)))

(define bar-body
  `(,@(safe-pop 'rax)
    ,@^-body
    (mov r14 rbx)
    (neg rbx)
    (cmp rax 0)
    (cmove r14 rbx)))

(define quote-body
  `((sub r15 ,quote-size)))

(define :-body
  `(,@(safe-pop 'rax)
    (push rax)
    (push rax)))

(define \-body
  `(,@(safe-pop 'rax)
    ,@(safe-pop 'rbx)
    (push rax)
    (push rbx)))

(define $-body
  `(,@(safe-pop 'rax)))

;; pop number and print decimal
(define .-body
  `(,@(safe-pop 'rdi)
    (mov rax write_num)
    (call rax)))

(define comma-body
  `((mov rax 1)   ; sys_write
    (mov rdi 1)   ; stdout
    (mov rsi rsp) ; top of stack
    (mov rdx 1)   ; one byte
    (syscall)
    ,@(safe-pop 'rax)))

;; skip next cell
;; jumps to the quote ramp of the next cell
;; fence cells deal with this entry point specially
(define bridge-body
  `((add r15 r14)
    (mov rax r15)
    (sub rax ,ramp-size)
    (jmp rax)))

;; the real fun times
;; pop byte off stack
(define p-body
  `(,@(safe-pop 'rdi) ; rdi <- y
    ,@(safe-pop 'rsi) ; rsi <- x
    ,@(safe-pop 'rdx) ; rdx <- char
    (mov rax put_cell)
    (jmp rax)))

(define g-body
  `(,@(safe-pop 'rdi) ; rdi <- y
    ,@(safe-pop 'rsi) ; rsi <- x
    (mov rax get_cell)
    (call rax)
    (push rax)))

;; read number
(define &-body
  `()) ;; TODO

;; read byte
(define ~-body
  `((xor rax rax) ; sys_read
    (xor rdi rdi) ; stdin
    (push rax)    ; allocate space on top of stack
    (mov rsi rsp) ; top of stack
    (mov rdx 1)   ; one byte
    (syscall)
    (mov rbx -1)
    (cmp rax 1)   ; if rax is zero, push -1 instead
    (cmove rbx [rsp])
    (mov [rsp] rbx)))

(define @-body
  `((mov rax 60)  ; sys_exit
    (xor rdi rdi) ; exit code 0
    (syscall)))

(define noop-body
  `())