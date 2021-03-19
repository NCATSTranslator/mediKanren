#lang racket/base
(provide
  fresh/p

  fail/p
  unit/p
  end

  single
  single-not
  one-of
  none-of

  many*
  many+
  many*-while
  many+-while
  many*-until
  many+-until

  skip*
  skip+
  skip*-while
  skip+-while
  skip*-until
  skip+-until

  seq

  and/p
  or/p

  peek
  remember1
  remember*
  ignore
  ignored
  )

(require
  "mk.rkt"
  )

(define (k/last&initial xs k)
  (define rxs (reverse xs))
  (k (car rxs) (reverse (cdr rxs))))

(define (appendo l s ls)
  (conde
    ((== '() l) (== s ls))
    ((fresh (a d ms)
       (== `(,a . ,d) l)
       (== `(,a . ,ms) ls)
       (appendo d s ms)))))

;; Common parser combinators
(define-syntax fresh/p
  (syntax-rules ()
    ((_ (vname ...) g ... p)
     (lambda (in out)
       (fresh (vname ...)
         g ...
         (p in out))))))

(define (fail/p in out) (== #t #f))
(define (unit/p in out) (== in out))
(define (end in out) (fresh () (== '() in) (== in out)))

(define (single d) (lambda (in out) (== `(,d . ,out) in)))
(define (single-lift d) (if (procedure? d) d (single d)))
(define (single-not d)
  (lambda (in out) (fresh (item) (== `(,item . ,out) in) (=/= item d))))

(define (seq2 pa pb) (lambda (in out) (fresh (mid) (pa in mid) (pb mid out))))
(define (seq . ds) (foldr seq2 unit/p (map single-lift ds)))

;; NOTE: and/p only commits with the last parser given.
(define (and2/p pa pb) (lambda (in out) (fresh (_) (pa in _) (pb in out))))
(define (and/p . ps)
  (if (null? ps) unit/p
    (k/last&initial ps (lambda (last initial) (foldr and2/p last initial)))))
(define (or2/p pa pb) (lambda (in out) (conde ((pa in out)) ((pb in out)))))
(define (or/p . ps) (foldr or2/p fail/p ps))

(define (one-of ds) (apply or/p (map single ds)))
(define (none-of ds) (apply and/p (map single-not ds)))

(define (peek p) (and/p p unit/p))
(define (remember1 p) (lambda (result) (and/p p (single result))))
(define (remember* p)
  (lambda (result)
    (lambda (in out)
      (fresh () (p in out) (appendo result out in)))))
(define (ignore p) (fresh/p (_) (p _)))
(define (ignored p) (lambda (result) p))

(define (many* pattern)
  (lambda (result)
    (or/p (fresh/p () (== '() result) unit/p)
          ((many+ pattern) result))))
(define (many+ pattern)
  (lambda (result)
    (fresh/p (first rest)
      (== `(,first . ,rest) result)
      (seq2 (pattern first) ((many* pattern) rest)))))
(define (many*-while ds)
  (lambda (result)
    (seq ((many* (remember1 (one-of ds))) result)
         (or/p end (peek (none-of ds))))))
(define (many+-while ds)
  (lambda (result) (seq (peek (one-of ds)) ((many*-while ds) result))))
(define (many*-until ds)
  (lambda (result)
    (seq ((many* (remember1 (none-of ds))) result)
         (or/p end (peek (one-of ds))))))
(define (many+-until ds)
  (lambda (result) (seq (peek (none-of ds)) ((many*-until ds) result))))

(define (skip* pattern) (ignore (many* (ignored pattern))))
(define (skip+ pattern) (ignore (many+ (ignored pattern))))
(define (skip*-while ds)
  (seq (skip* (one-of ds)) (or/p end (peek (none-of ds)))))
(define (skip+-while ds) (seq (peek (one-of ds)) (skip* (one-of ds))))
(define (skip*-until ds)
  (seq (skip* (none-of ds)) (or/p end (peek (one-of ds)))))
(define (skip+-until ds) (seq (peek (none-of ds)) (skip*-until ds)))
