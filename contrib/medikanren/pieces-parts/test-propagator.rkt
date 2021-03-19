#lang racket
(provide
  (all-from-out "../../../medikanren/pieces-parts/common.rkt")
  (all-from-out "../../../medikanren/pieces-parts/mk-db.rkt")
  (all-from-out "../../../medikanren/pieces-parts/propagator.rkt")
  (all-defined-out))
(require "../../../medikanren/common.rkt" "../../../medikanren/mk-db.rkt" "../../../medikanren/pieces-parts/propagator.rkt")
(load-databases #t)

(define positively-regulates '("causes"))
(define negatively-regulates '("negatively_regulates"))

(define imatinib "UMLS:C0935989")
(define asthma   "UMLS:C0004096")

(define S (concept/curie imatinib))
(define X (concept/any))
(define O (concept/curie asthma))

(define S->X (edge/predicate negatively-regulates S X))
(define X->O (edge/predicate positively-regulates X O))

(displayln 'running:)
(time (run!))

(displayln 'S)
(length (cdr (S 'ref)))

(displayln 'O)
(length (cdr (O 'ref)))

(displayln 'X)
(length (cdr (X 'ref)))

(displayln 'S->X)
(length (cdr (S->X 'ref)))

(displayln 'X->O)
(length (cdr (X->O 'ref)))
