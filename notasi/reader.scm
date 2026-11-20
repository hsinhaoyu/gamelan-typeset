;;; (notasi reader) -- Read notation (.gml) into a piece.
;;; See doc/design/03-reader.md.
;;;
;;; Slice 1: the public interface, &notasi-syntax-error, reading forms,
;;; dispatch, and the `piece` form.  Other known forms raise
;;; `not-implemented` until their slice is built.

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

(define (option-line option form-line)
  (match (and (pair? option) (source-property option 'line))
    ((? integer? line) (1+ line))
    (_ form-line)))

(define (parse-option option form-line seen)
  "Check OPTION and return SEEN, an alist of options so far, with it added."
  (let ((line (option-line option form-line)))
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
;;; Entry points

(define (read-piece forms)
  "Check FORMS, a list of (DATUM . LINE), and build the piece."
  (for-each check-form forms)
  (let ((piece (parse-piece-form (find-piece-form forms))))
    ;; Step 5: later slices handle the other forms.
    (match (remove piece-form? forms)
      (() piece)
      ((((head . _) . line) . _)
       (syntax-error 'not-implemented line
                     "the `~a' form is not supported yet" head)))))

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
