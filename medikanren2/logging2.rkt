#lang racket
(provide
  lognew-info lognew-error requestid)
(require
  racket/date
  json
)
(define requestid (make-parameter -1))

(date-display-format 'iso-8601)

(define (lognew-message level msg)
  (define t (current-seconds))
  (define st-t (date->string (seconds->date t #f) #t))
  (define jsexpr
    (if (hash? msg)
      (hash-set
        (hash-set
          (hash-set msg
            'level (symbol->string level))
          'requestid (requestid))
        't st-t)
      (hasheq
        'msg msg
        't st-t
        'requestid (requestid)
        'level (symbol->string level))))
  (with-handlers ([exn:fail?
                   (λ (e)
                     (printf
                      "Caught exception in lognew-message when converting/printing jsexpr->string.\nlevel:\n~s\nmsg:\n~s\njsexpr:\n~s\nexception:\n~s\n"
                      level
                      msg
                      jsexpr
                      e))])
    (displayln
     (jsexpr->string jsexpr)))
  (flush-output (current-output-port)))

(define (lognew-info msg)
  (lognew-message 'info msg))

(define (lognew-error msg)
  (lognew-message 'error msg))

