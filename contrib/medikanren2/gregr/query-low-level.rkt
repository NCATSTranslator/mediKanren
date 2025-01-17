#lang racket/base
(provide
  query:Known->Known
  query:Known->X
  query:X->Known
  query:Known<-X->Known
  query:X->Y->Known
  query:Prefix->Prefix
  query:Concept
  edge-properties
  edge-property-values
  concept-properties
  concept-property-values
  )
(require
  "../../../medikanren2/dbk/dbk/data.rkt"
  "../../../medikanren2/dbk/dbk/enumerator.rkt"
  "../../../medikanren2/dbk/dbk/stream.rkt"
  racket/match
  racket/runtime-path
  racket/set
  racket/string
  )

;;;;;;;;;;;;;;;
;; Utilities ;;
;;;;;;;;;;;;;;;
(define (dict-select d key) (d 'ref key (lambda (v) v) (lambda () (error "dict ref failed" key))))

;; TODO: build small in-memory relations more easily
(define (strings->dict strs)
  (define vec.strs  (list->vector (sort (set->list (list->set strs)) string<?)))
  (define dict.strs (dict:ordered (column:vector vec.strs) (column:const '()) 0 (vector-length vec.strs)))
  (define vec.ids   (enumerator->vector
                      (lambda (yield)
                        ((merge-join dict.strs dict.string=>id)
                         (lambda (__ ___ id) (yield id))))))
  (dict:ordered (column:vector vec.ids) (column:const '()) 0 (vector-length vec.ids)))

;; TODO: we don't need before and after, we can find a finite delimiter in the lexicographical ordering
;; (integer->char (+ 1 (char->integer #\:))) ==> #\;
(define (dict-string-prefix prefix)
  (define d.string=>id
    ((dict.string=>id 'after (lambda (str) (string<? str prefix)))
     'before (lambda (str) (and (string<? prefix str)
                                (not (string-prefix? str prefix))))))
  (define start (d.string=>id 'top))
  (define end   (+ start (d.string=>id 'count)))
  ((dict.id=>string '>= start) '< end))

;(define (edge-id->properties eid)
  ;(define (get id default)
    ;(eprops 'ref id
            ;(lambda (dict.value) (dict-select dict.id=>string (dict.value 'min)))
            ;(lambda ()           default)))
  ;(define eprops       (dict-select dict.eprop:value.key.eid eid))
  ;(define negated      (get id.negated ""))
  ;(define provided-by  (get id.provided-by ""))
  ;(define publications (get id.publications ""))
  ;(list negated provided-by publications))

(define-runtime-path path.here ".")
(define db      (database (path->string (build-path path.here "rtx-kg2_20210204.db"))))
(define r.cprop (database-relation db '(rtx-kg2 cprop)))
(define r.edge  (database-relation db '(rtx-kg2 edge)))
(define r.eprop (database-relation db '(rtx-kg2 eprop)))

(define domain-dicts                 (relation-domain-dicts r.cprop))
(define dict.string=>id              (car (hash-ref (car domain-dicts) 'text)))
(define dict.id=>string              (car (hash-ref (cdr domain-dicts) 'text)))

(define dict.edge:object.eid.subject (relation-index-dict r.edge  '(subject eid object)))
(define dict.edge:subject.eid.object (relation-index-dict r.edge  '(object eid subject)))
(define dict.eprop:eid.value.key     (relation-index-dict r.eprop '(key value eid)))
(define dict.eprop:value.key.eid     (relation-index-dict r.eprop '(eid key value)))
(define dict.cprop:curie.value.key   (relation-index-dict r.cprop '(key value curie)))
(define dict.cprop:value.key.curie   (relation-index-dict r.cprop '(curie key value)))

(define id.negated      (dict-select dict.string=>id "negated"))
(define id.provided-by  (dict-select dict.string=>id "provided_by"))
(define id.publications (dict-select dict.string=>id "publications"))


;; Testing

(require racket/pretty)

(define (f2 str.relation)
  (define (query yield)
    (define id.ekey              (dict-select dict.string=>id "relation"))
    (define id.relation          (dict-select dict.string=>id str.relation))
    (define dict.eprop:eid.value (dict-select dict.eprop:eid.value.key id.ekey))
    (define dict.eprop:eid       (dict-select dict.eprop:eid.value     id.relation))
    ((merge-join dict.eprop:eid dict.eprop:value.key.eid)
     (lambda (eid __ dict.eprop:value.key)
       (yield (list eid (enumerator->list
                          (lambda (yield)
                            ((dict.eprop:value.key 'enumerator/2)
                             (lambda (id.key dict.eprop:value)
                               (define str.key (dict-select dict.id=>string id.key))
                               ((dict.eprop:value 'enumerator)
                                (lambda (id.value)
                                  (define str.value (dict-select dict.id=>string id.value))
                                  (yield (cons str.key str.value)))))))))))))
  (time (enumerator->rlist query)))

(define results.f2 (f2 "DGIdb:binder"))

(pretty-write (length results.f2))

(read-line)
(pretty-write results.f2)

;; query:Known->X is analogous to a miniKanren-style query with this shape:
; (run* (s sname p o oname)
;   (fresh (id category)
;     (edge id s o)
;     (cprop o "category" category)
;     (cprop s "name" sname)
;     (cprop o "name" oname)
;     (eprop id "predicate" p)
;     (membero s subject-curies)
;     (membero p predicates)
;     (membero category object-categories)))

(define (query:Known->X curies.K predicates.K->X categories.X)
  (define (query yield)
    (define ekey.predicate.id         (dict-select dict.string=>id "predicate"))
    (define ckey.category.id          (dict-select dict.string=>id "category"))
    (define ckey.name.id              (dict-select dict.string=>id "name"))
    (define dict.curies.K             (strings->dict curies.K))
    (define dict.predicates.K->X      (strings->dict predicates.K->X))
    (define dict.categories.X         (strings->dict categories.X))
    (define dict.eprop.eid.predicate  (dict-select dict.eprop.eid.value.key   ekey.predicate.id))
    (define dict.cprop.curie.category (dict-select dict.cprop.curie.value.key ckey.category.id))
    ((merge-join dict.curies.K dict.edge.object.eid.subject)
     (lambda (id.K __ dict.edge.X.eid)
       (define id.name.K ((dict-select (dict-select dict.cprop.value.key.curie id.K) ckey.name.id) 'min))
       (define name.K    (dict-select dict.id=>string id.name.K))
       (define K         (dict-select dict.id=>string id.K))
       ((merge-join dict.predicates.K->X dict.eprop.eid.predicate)
        (lambda (id.predicate.K->X __ dict.eprop.K->X)
          (define predicate.K->X (dict-select dict.id=>string id.predicate.K->X))
          ((merge-join dict.eprop.K->X dict.edge.X.eid)
           (lambda (eid __ dict.edge.X)
             (define props (edge-id->properties eid))
             ((merge-join dict.categories.X dict.cprop.curie.category)
              (lambda (__ ___ dict.cprop.X)
                ((dict-join-ordered
                   (lambda (yield)
                     ((merge-join dict.cprop.X dict.edge.X)
                      (lambda (id.X __ ___)
                        (yield id.X '()))))
                   dict.cprop.value.key.curie)
                 (lambda (id.X __ dict.cprop.value.key)
                   (define id.name.X ((dict-select dict.cprop.value.key ckey.name.id) 'min))
                   (define name.X    (dict-select dict.id=>string id.name.X))
                   (define X         (dict-select dict.id=>string id.X))
                   (yield (list* K name.K predicate.K->X X name.X props)))))))))))))
  (time (enumerator->rlist query)))

;;; query:X->Known is analogous to a miniKanren-style query with this shape:
;; (run* (s sname p o oname)
;;   (fresh (id category)
;;     (edge id s o)
;;     (cprop s "category" category)
;;     (cprop s "name" sname)
;;     (cprop o "name" oname)
;;     (eprop id "predicate" p)
;;     (membero o object-curies)
;;     (membero p predicates)
;;     (membero category subject-categories)))

;(define (query:X->Known categories.X predicates.X->K curies.K)
  ;(define (query yield)
    ;(define ekey.predicate.id         (dict-select dict.string=>id "predicate"))
    ;(define ckey.category.id          (dict-select dict.string=>id "category"))
    ;(define ckey.name.id              (dict-select dict.string=>id "name"))
    ;(define dict.categories.X         (strings->dict categories.X))
    ;(define dict.predicates.X->K      (strings->dict predicates.X->K))
    ;(define dict.curies.K             (strings->dict curies.K))
    ;(define dict.eprop.eid.predicate  (dict-select dict.eprop.eid.value.key   ekey.predicate.id))
    ;(define dict.cprop.curie.category (dict-select dict.cprop.curie.value.key ckey.category.id))
    ;((merge-join dict.curies.K dict.edge.subject.eid.object)
     ;(lambda (id.K __ dict.edge.X.eid)
       ;(define id.name.K ((dict-select (dict-select dict.cprop.value.key.curie id.K) ckey.name.id) 'min))
       ;(define name.K    (dict-select dict.id=>string id.name.K))
       ;(define K         (dict-select dict.id=>string id.K))
       ;((merge-join dict.predicates.X->K dict.eprop.eid.predicate)
        ;(lambda (id.predicate.X->K __ dict.eprop.X->K)
          ;(define predicate.X->K (dict-select dict.id=>string id.predicate.X->K))
          ;((merge-join dict.eprop.X->K dict.edge.X.eid)
           ;(lambda (eid __ dict.edge.X)
             ;(define props (edge-id->properties eid))
             ;((merge-join dict.categories.X dict.cprop.curie.category)
              ;(lambda (__ ___ dict.cprop.X)
                ;((dict-join-ordered
                   ;(lambda (yield)
                     ;((merge-join dict.cprop.X dict.edge.X)
                      ;(lambda (id.X __ ___)
                        ;(yield id.X '()))))
                   ;dict.cprop.value.key.curie)
                 ;(lambda (id.X __ dict.cprop.value.key)
                   ;(define id.name.X ((dict-select dict.cprop.value.key ckey.name.id) 'min))
                   ;(define name.X    (dict-select dict.id=>string id.name.X))
                   ;(define X         (dict-select dict.id=>string id.X))
                   ;(yield (list* X name.X predicate.X->K K name.K props)))))))))))))
  ;(time (enumerator->rlist query)))

;;; query:Known<-X->Known is analogous to a miniKanren-style query with this shape:
;;(run* (K1 name.K1 predicates.K1<-X X name.X predicates.X->K1 K2 name.K2)
;;  (fresh (id1 id2 category.X)
;;    (edge id1 X K1)
;;    (edge id2 X K2)
;;    (cprop X   "category" category.X)
;;    (cprop X   "name" name.X)
;;    (cprop K1  "name" name.K1)
;;    (cprop K2  "name" name.K2)
;;    (eprop id1 "predicate" K1<-X)
;;    (eprop id2 "predicate" X->K2)
;;    (membero category.X categories.X)
;;    (membero K1         curies.K1)
;;    (membero K1<-X      predicates.K1<-X)
;;    (membero K2         curies.K2)
;;    (membero X->K2      predicates.X->K2)))

;(define (query:Known<-X->Known curies.K1 predicates.K1<-X categories.X predicates.X->K2 curies.K2)
  ;(define (candidates->dict candidates)
    ;(define ordered (sort candidates (lambda (a b) (string<? (car a) (car b)))))
    ;(define groups  (s-group ordered equal? car))
    ;(dict:ordered:vector (list->vector groups) caar))
  ;(define candidates.X->K1 (query:X->Known categories.X predicates.K1<-X curies.K1))
  ;(define candidates.X->K2 (query:X->Known categories.X predicates.X->K2 curies.K2))
  ;(define dict.X->K1.X     (candidates->dict candidates.X->K1))
  ;(define dict.X->K2.X     (candidates->dict candidates.X->K2))
  ;(time (enumerator->list
          ;(lambda (yield)
            ;((merge-join dict.X->K1.X dict.X->K2.X)
             ;(lambda (X XK1s XK2s)
               ;(for-each (lambda (XK1)
                           ;(match-define (list* _ name.X X->K1 K1 name.K1 props1) XK1)
                           ;(for-each (lambda (XK2)
                                       ;(match-define (list* _ _ X->K2 K2 name.K2 props2) XK2)
                                       ;(yield (append (list K1 name.K1 X->K1 X name.X X->K2 K2 name.K2)
                                                      ;(append props1 props2))))
                                     ;XK2s))
                         ;XK1s)))))))

;(define (query:X->Y->Known categories.X predicates.X->Y categories.Y predicates.Y->K curies.K)
  ;(define (results->dict key results)
    ;(define ordered (sort results (lambda (a b) (string<? (key a) (key b)))))
    ;(define groups  (s-group ordered equal? key))
    ;(dict:ordered:vector (list->vector groups) (lambda (x) (key (car x)))))
  ;(define results.Y->K (query:X->Known categories.Y predicates.Y->K curies.K))
  ;(define dict.Y->K.Y  (results->dict car results.Y->K))
  ;(define curies.Y     (enumerator->list (dict.Y->K.Y 'enumerator)))
  ;(define results.X->Y (query:X->Known categories.X predicates.X->Y curies.Y))
  ;(define dict.X->Y.Y  (results->dict cadddr results.X->Y))
  ;(time (enumerator->list
          ;(lambda (yield)
            ;((merge-join dict.X->Y.Y dict.Y->K.Y)
             ;(lambda (Y XYs YKs)
               ;(for-each (lambda (XY)
                           ;(match-define (list* X name.X X->Y _ name.Y props.X->Y) XY)
                           ;(for-each (lambda (YK)
                                       ;(match-define (list* _ _ Y->K K name.K props.Y->K) YK)
                                       ;(yield (append (list X name.X X->Y Y name.Y Y->K K name.K)
                                                      ;(append props.X->Y props.Y->K))))
                                     ;YKs))
                         ;XYs)))))))

;(define (query:Known->Known curies.S predicates.S->O curies.O)
  ;(define dict.curies.S (strings->dict curies.S))
  ;(define dict.curies.O (strings->dict curies.O))
  ;(query:dict.Known->dict.Known dict.curies.S predicates.S->O dict.curies.O))

;(define (query:Prefix->Prefix prefix.S predicates.S->O prefix.O)
  ;(define dict.curies.S (dict-string-prefix prefix.S))
  ;(define dict.curies.O (dict-string-prefix prefix.O))
  ;(query:dict.Known->dict.Known dict.curies.S predicates.S->O dict.curies.O))

;(define (query:dict.Known->dict.Known dict.curies.S predicates.S->O dict.curies.O)
  ;(define (query yield)
    ;(define ekey.predicate.id         (dict-select dict.string=>id "predicate"))
    ;(define ckey.category.id          (dict-select dict.string=>id "category"))
    ;(define ckey.name.id              (dict-select dict.string=>id "name"))
    ;(define dict.predicates.S->O      (strings->dict predicates.S->O))
    ;(define dict.eprop.eid.predicate  (dict-select dict.eprop.eid.value.key   ekey.predicate.id))
    ;(define dict.cprop.curie.category (dict-select dict.cprop.curie.value.key ckey.category.id))
    ;((merge-join dict.curies.S dict.edge.object.eid.subject)
     ;(lambda (id.S __ dict.edge.O.eid)
       ;(define id.name.S ((dict-select (dict-select dict.cprop.value.key.curie id.S) ckey.name.id) 'min))
       ;(define name.S    (dict-select dict.id=>string id.name.S))
       ;(define S         (dict-select dict.id=>string id.S))
       ;((merge-join dict.predicates.S->O dict.eprop.eid.predicate)
        ;(lambda (id.predicate.S->O __ dict.eprop.S->O)
          ;(define predicate.S->O (dict-select dict.id=>string id.predicate.S->O))
          ;((merge-join dict.eprop.S->O dict.edge.O.eid)
           ;(lambda (eid __ dict.edge.O)
             ;(define props (edge-id->properties eid))
             ;((merge-join dict.curies.O dict.edge.O)
              ;(lambda (id.O __ ___)
                ;(define id.name.O ((dict-select (dict-select dict.cprop.value.key.curie id.O) ckey.name.id) 'min))
                ;(define name.O    (dict-select dict.id=>string id.name.O))
                ;(define O         (dict-select dict.id=>string id.O))
                ;(yield (list* S name.S predicate.S->O O name.O props)))))))))))
  ;(time (enumerator->rlist query)))

;(define (query:Concept curies)
  ;(define (query yield)
    ;(define dict.curie (strings->dict curies))
    ;((merge-join dict.curie dict.cprop.value.key.curie)
     ;(lambda (id.curie _ dict.cprop.value.key)
       ;(define curie (dict-select dict.id=>string id.curie))
       ;((dict.cprop.value.key 'enumerator/2)
        ;(lambda (id.key dict.cprop.value)
          ;(define key   (dict-select dict.id=>string id.key))
          ;(define value (dict-select dict.id=>string (dict.cprop.value 'min)))
          ;(yield (list curie key value)))))))
  ;(time (enumerator->list query)))

;(define (concept-properties)          (enumerator->list
                                        ;(lambda (yield)
                                          ;((merge-join dict.cprop.curie.value.key dict.id=>string)
                                           ;(lambda (_ __ key)
                                             ;(yield key))))))
;(define (edge-properties)             (enumerator->list
                                        ;(lambda (yield)
                                          ;((merge-join dict.eprop.eid.value.key dict.id=>string)
                                           ;(lambda (_ __ key)
                                             ;(yield key))))))
;(define (concept-property-values key) (enumerator->list
                                        ;(lambda (yield)
                                          ;((merge-join (dict-select dict.cprop.curie.value.key (dict-select dict.string=>id key))
                                                       ;dict.id=>string)
                                           ;(lambda (_ __ value) (yield value))))))
;(define (edge-property-values    key) (enumerator->list
                                        ;(lambda (yield)
                                          ;((merge-join (dict-select dict.eprop.eid.value.key   (dict-select dict.string=>id key))
                                                       ;dict.id=>string)
                                           ;(lambda (_ __ value) (yield value))))))



