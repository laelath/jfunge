#lang racket

(require "jfunge.rkt")

(provide main)

(define (main fn)
  (with-input-from-file fn
    (λ ()
      (let ([p (read-program)])
        (display fn)
        (compile p)))))

(define (read-program)
  (port->string))