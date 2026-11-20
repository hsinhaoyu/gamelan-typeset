;;; (notasi reader) -- Read notation (.gml) into a piece.
;;; See doc/design/03-reader.md.
;;;
;;; Slice 1: the public interface, &notasi-syntax-error, reading forms,
;;; dispatch, and the `piece` form.  Slice 2: scales, stroke sets and
;;; instruments.  Other known forms raise `not-implemented` until their
;;; slice is built.

(define-module (notasi reader)
  #:use-module (notasi piece)
  #:use-module (ice-9 exceptions)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (read-piece-file
            read-piece-port
            read-piece-string

            &notasi-syntax-error
            notasi-syntax-error?
            notasi-syntax-error-kind
            notasi-syntax-error-file
            notasi-syntax-error-line
            notasi-syntax-error-part
            notasi-syntax-error-step))

;;; ------------------------------------------------------------------
;;; The condition type

(define &notasi-syntax-error
  (make-exception-type '&notasi-syntax-error &error
                       '(kind file line part step)))

(define make-notasi-syntax-error
  (record-constructor &notasi-syntax-error))

(define notasi-syntax-error?
  (exception-predicate &notasi-syntax-error))

(define-syntax-rule (define-field-accessors (accessor field) ...)
  (begin
    (define accessor
      (exception-accessor &notasi-syntax-error
                          (record-accessor &notasi-syntax-error 'field)))
    ...))

(define-field-accessors
  (notasi-syntax-error-kind kind)
  (notasi-syntax-error-file file)
  (notasi-syntax-error-line line)
  (notasi-syntax-error-part part)
  (notasi-syntax-error-step step))

;;; The file being read, or #f for a string or port.  Set once per read,
;;; so error reports don't need it passed through every check.
(define current-source-file (make-parameter #f))

(define (syntax-error kind line fmt . args)
  "Raise a &notasi-syntax-error of KIND at LINE (1-based, or #f) in the
current source file, with a message built from FMT and ARGS."
  (let ((file (current-source-file)))
    (raise-exception
     (make-exception
      (make-notasi-syntax-error kind file line #f #f)
      (make-exception-with-message
       (format #f "~a~@[:~a~]: ~?" (or file "<string>") line fmt args))))))

;;; ------------------------------------------------------------------
;;; Step 1: read forms

(define (read-error? e)
  ;; exception-kind returns '%exception for conditions with no kind.
  (eq? (exception-kind e) 'read-error))

(define (read-forms port)
  "Read every datum from PORT.  Return a list of (DATUM . LINE), with
1-based lines: a list's own line, or for an atom the line where it ends."
  (define (next)
    (guard (e ((read-error? e)
               (syntax-error 'read-error (1+ (port-line port))
                             "cannot read the notation (~a)"
                             (exception-message-text e))))
      (read port)))
  (let loop ((forms '()))
    (let ((datum (next)))
      (if (eof-object? datum)
          (reverse forms)
          (loop (cons (cons datum (datum-line datum port)) forms))))))

(define (datum-line datum port)
  (match (and (pair? datum) (source-property datum 'line))
    ((? integer? line) (1+ line))
    (_ (1+ (port-line port)))))

(define (exception-message-text e)
  "The text of Guile's read error E, with its format arguments applied."
  (match (exception-args e)
    ((_ fmt args . _) (apply format #f fmt (or args '())))
    (_ "read error")))

;;; ------------------------------------------------------------------
;;; Step 2: dispatch

(define known-heads
  '(piece use scale strokes instrument part group text))

(define (check-form form)
  "Raise an error unless FORM, a (DATUM . LINE) pair, is a proper list
with a known head symbol."
  (match form
    (((? pair? datum) . line)
     (unless (list? datum)
       (syntax-error 'improper-form line
                     "a form contains a lone `.'; use `-' or `·' for a rest"))
     (unless (memq (car datum) known-heads)
       (syntax-error 'unknown-form line "unknown form `~s'" (car datum))))
    ((datum . line)
     (syntax-error 'unknown-form line "~s is not a form" datum))))

;;; ------------------------------------------------------------------
;;; Step 3: the piece form is present, first and only once

(define (piece-form? form)
  (eq? (car (car form)) 'piece))

(define (find-piece-form forms)
  "Return the (DATUM . LINE) of the only `piece' form, which must be the
first form."
  (match (filter piece-form? forms)
    (() (syntax-error 'missing-piece #f "no (piece TITLE ...) form"))
    ((first . rest)
     (unless (eq? first (car forms))
       (syntax-error 'piece-not-first (cdr (car forms))
                     "the (piece ...) form must come first"))
     (match rest
       (() first)
       (((_ . line) . _)
        (syntax-error 'duplicate-piece line "a second (piece ...) form"))))))

;;; ------------------------------------------------------------------
;;; Step 4: the piece form's title and options

(define piece-options '(steps-per-pulse steps-per-system))

(define (list-line datum fallback)
  "The 1-based line of DATUM if it is a list read with a position, else
FALLBACK.  Atoms carry no position."
  (match (and (pair? datum) (source-property datum 'line))
    ((? integer? line) (1+ line))
    (_ fallback)))

(define (parse-option option form-line seen)
  "Check OPTION and return SEEN, an alist of options so far, with it added."
  (let ((line (list-line option form-line)))
    (match option
      (((? symbol? name) value)
       (unless (memq name piece-options)
         (syntax-error 'unknown-option line "unknown piece option `~a'" name))
       (when (assq name seen)
         (syntax-error 'duplicate-option line "option `~a' given twice" name))
       (unless (and (exact-integer? value) (positive? value))
         (syntax-error 'bad-option line
                       "`~a' must be a positive whole number, not ~s"
                       name value))
       (acons name value seen))
      (_ (syntax-error 'bad-option line
                       "a piece option must be (NAME VALUE), not ~s"
                       option)))))

(define (parse-piece-form form)
  "Build a piece with no parts from the `piece' form FORM, a (DATUM . LINE)."
  (match form
    ((('piece (? string? title) . options) . line)
     (let ((opts (fold (lambda (option seen) (parse-option option line seen))
                       '() options)))
       (make-piece title
                   (or (assq-ref opts 'steps-per-pulse) 4)
                   (assq-ref opts 'steps-per-system)
                   0 '() '() '() '())))
    ((_ . line)
     (syntax-error 'bad-title line
                   "the piece needs a title string: (piece \"Title\" ...)"))))

;;; ------------------------------------------------------------------
;;; Selecting forms

(define (form-head form)
  (car (car form)))

(define (forms-with-heads forms heads)
  "The forms in FORMS, a list of (DATUM . LINE), whose head is in HEADS,
in file order."
  (filter (lambda (form) (memq (form-head form) heads)) forms))

(define (location line)
  (make-source-location (current-source-file) line))

(define (check-not-implemented forms heads)
  "Raise `not-implemented' at the first form whose head is in HEADS."
  (match (forms-with-heads forms heads)
    (() #t)
    ((((head . _) . line) . _)
     (syntax-error 'not-implemented line
                   "the `~a' form is not supported yet" head))))

;;; ------------------------------------------------------------------
;;; Item 6: the shape of scale, strokes and instrument forms

(define definition-heads '(scale strokes instrument))

(define (check-definition-shape form)
  (match form
    ((((or 'scale 'strokes) (? symbol?) _ ..1) . _) #t)
    ((('instrument (? symbol?) (? symbol?) (? symbol?) ..1) . _) #t)
    ((('scale . _) . line)
     (syntax-error 'bad-form line
                   "a scale needs a name and its degrees: (scale NAME DEGREE ...)"))
    ((('strokes . _) . line)
     (syntax-error 'bad-form line
                   "a stroke set needs a name and its strokes: (strokes NAME STROKE ...)"))
    ((('instrument . _) . line)
     (syntax-error 'bad-form line
                   "an instrument needs a name, a scale or stroke set, and its notes: (instrument NAME SCALE NOTE ...)"))))

;;; ------------------------------------------------------------------
;;; Item 7: duplicate definitions.  Scales and stroke sets share one set
;;; of names, since an instrument refers to either; instruments have
;;; their own.

(define (check-duplicates definitions)
  (fold (lambda (form seen)
          (match form
            (((head name . _) . line)
             (let ((key (cons (if (eq? head 'instrument) 'instrument 'scale)
                              name)))
               (when (member key seen)
                 (syntax-error 'duplicate-definition line
                               "`~a' is already defined in this file" name))
               (cons key seen)))))
        '()
        definitions))

;;; ------------------------------------------------------------------
;;; Item 8: scales and stroke sets

(define (ascii-digit? c)
  (and (char<=? #\0 c) (char<=? c #\9)))

(define (ends-in-digit? name)
  (let ((s (symbol->string name)))
    (and (not (string-null? s))
         (ascii-digit? (string-ref s (1- (string-length s)))))))

(define (parse-degree-option option seen bad)
  "Check one degree OPTION and return SEEN, an alist of options so far,
with it added.  BAD raises a `bad-degree' error."
  (match option
    (((and key (or 'alias 'display)) . _)
     (when (assq key seen)
       (bad "option `~a' given twice" key))
     (match option
       (('alias (? symbol? names) ..1) (acons 'alias names seen))
       (('display (? string? text)) (acons 'display text seen))
       (('alias . _) (bad "(alias NAME ...) needs one or more names"))
       (('display . _) (bad "(display \"TEXT\") needs exactly one string"))))
    (_ (bad "unknown option ~s; a degree takes (alias NAME ...) and (display \"TEXT\")"
            option))))

(define (parse-degree datum set-line)
  "Build a degree record from DATUM: a name, or (NAME OPTION ...).  A
bare name has no position, so it takes SET-LINE, its scale's line."
  (let ((line (list-line datum set-line)))
    (define (bad fmt . args)
      (apply syntax-error 'bad-degree line fmt args))
    (match datum
      ((? symbol? name)
       (make-degree name '() (symbol->string name) (location line)))
      (((? symbol? name) . (? list? options))
       (let ((opts (fold (lambda (option seen)
                           (parse-degree-option option seen bad))
                         '() options)))
         (make-degree name
                      (or (assq-ref opts 'alias) '())
                      (or (assq-ref opts 'display) (symbol->string name))
                      (location line))))
      (_ (bad "a degree must be a name or (NAME OPTION ...), not ~s" datum)))))

(define (degree-names degree)
  (cons (degree-name degree) (degree-aliases degree)))

(define (build-scale form)
  "Build a scale record from a `scale' or `strokes' FORM."
  (match form
    (((head name . data) . set-line)
     (let ((pitched? (eq? head 'scale)))
       (let loop ((data data) (used '()) (degrees '()))
         (match data
           (()
            (make-scale name (reverse degrees) pitched? (location set-line)))
           ((datum . rest)
            (let* ((degree (parse-degree datum set-line))
                   (line (source-location-line (degree-location degree))))
              (when pitched?
                (for-each
                 (lambda (n)
                   (when (ends-in-digit? n)
                     (syntax-error 'degree-ends-in-digit line
                                   "scale `~a': `~a' ends in a digit, which would be read as an octave"
                                   name n)))
                 (degree-names degree)))
              (loop rest
                    (fold (lambda (n used)
                            (when (memq n used)
                              (syntax-error 'duplicate-degree line
                                            "`~a' is used twice in `~a'" n name))
                            (cons n used))
                          used
                          (degree-names degree))
                    (cons degree degrees))))))))))

;;; ------------------------------------------------------------------
;;; Item 9: instruments

(define (name-table scale)
  "An alist from every degree name and alias of SCALE to its index."
  (append-map (lambda (degree i)
                (map (lambda (n) (cons n i)) (degree-names degree)))
              (scale-degrees scale)
              (iota (length (scale-degrees scale)))))

(define (split-octave name)
  "Split NAME, e.g. ding2, into (ding . 2).  Return #f if NAME has no
octave number, or one with a leading zero (only 0 itself may start
with 0)."
  (let* ((s (symbol->string name))
         (end (string-index-right s (lambda (c) (not (ascii-digit? c)))))
         (digits (if end (substring s (1+ end)) "")))
    (and end
         (not (string-null? digits))
         (or (string=? digits "0")
             (not (char=? (string-ref digits 0) #\0)))
         (cons (string->symbol (substring s 0 (1+ end)))
               (string->number digits)))))

(define (resolve-note name scale table instrument line)
  "The note record for NAME on INSTRUMENT, whose scale is SCALE."
  (define (canonical i)
    (degree-name (list-ref (scale-degrees scale) i)))
  (define (unknown)
    (syntax-error 'unknown-note line
                  "instrument `~a': `~a' is not a note of `~a'"
                  instrument name (scale-name scale)))
  (if (scale-pitched? scale)
      (match (split-octave name)
        (#f (if (assq name table)
                (syntax-error 'unknown-note line
                              "instrument `~a': `~a' needs an octave number, e.g. ~a1"
                              instrument name name)
                (unknown)))
        ((degree . octave)
         (match (assq degree table)
           (#f (unknown))
           ((_ . i)
            (make-note (symbol-append (canonical i)
                                      (string->symbol (number->string octave)))
                       i octave)))))
      (match (assq name table)
        (#f (unknown))
        ((_ . i) (make-note (canonical i) i #f)))))

(define (pitch<? a b)
  (or (< (note-octave a) (note-octave b))
      (and (= (note-octave a) (note-octave b))
           (< (note-degree a) (note-degree b)))))

(define (check-note-order note earlier pitched? instrument line)
  "Check NOTE against EARLIER, the notes before it, latest first."
  (if pitched?
      (match earlier
        ((previous . _)
         (unless (pitch<? previous note)
           (syntax-error 'notes-not-ascending line
                         "instrument `~a': `~a' comes after `~a'; list notes from low to high"
                         instrument (note-name note) (note-name previous))))
        (() #t))
      (when (any (lambda (n) (= (note-degree n) (note-degree note))) earlier)
        (syntax-error 'duplicate-note line
                      "instrument `~a': `~a' is listed twice"
                      instrument (note-name note)))))

(define (build-instrument form scales)
  "Build an instrument record from FORM.  SCALES is an alist from name to
scale record."
  (match form
    ((('instrument name scale-name . note-names) . line)
     (let* ((scale (or (assq-ref scales scale-name)
                       (syntax-error 'undefined-scale line
                                     "instrument `~a': no scale or stroke set called `~a'"
                                     name scale-name)))
            (table (name-table scale))
            (notes (fold (lambda (note-name earlier)
                           (let ((note (resolve-note note-name scale table
                                                     name line)))
                             (check-note-order note earlier
                                               (scale-pitched? scale) name line)
                             (cons note earlier)))
                         '()
                         note-names)))
       (make-instrument name scale (list->vector (reverse notes))
                        (location line))))))

;;; ------------------------------------------------------------------
;;; Entry points

(define (read-piece forms)
  "Check FORMS, a list of (DATUM . LINE), and build the piece.  The
checks run in the order given in 03-reader.md, so a file with several
problems always reports the same one."
  (for-each check-form forms)
  (let ((piece (parse-piece-form (find-piece-form forms))))
    (check-not-implemented forms '(use))       ; slice 4
    (let ((definitions (forms-with-heads forms definition-heads)))
      (for-each check-definition-shape definitions)
      (check-duplicates definitions))
    (let* ((scales (map (lambda (form)
                          (let ((scale (build-scale form)))
                            (cons (scale-name scale) scale)))
                        (forms-with-heads forms '(scale strokes))))
           (instruments (map (lambda (form) (build-instrument form scales))
                             (forms-with-heads forms '(instrument)))))
      (check-not-implemented forms '(part group text))   ; slice 3; text is v2
      (make-piece (piece-title piece)
                  (piece-steps-per-pulse piece)
                  (piece-steps-per-system piece)
                  0 (map cdr scales) instruments '() '()))))

(define* (read-piece-port port #:key directory)
  "Read a piece from PORT.  Raise a &notasi-syntax-error on any error.
DIRECTORY is where `(use \"file.gml\")' looks (not used yet)."
  (read-piece (read-forms port)))

(define* (read-piece-string str #:key directory)
  "Read a piece from the string STR.  See `read-piece-port'."
  (call-with-input-string str
    (lambda (port) (read-piece-port port #:directory directory))))

(define (read-piece-file path)
  "Read a piece from the file at PATH.  Errors report PATH as their file."
  (parameterize ((current-source-file path))
    (call-with-input-file path read-piece-port)))
