;;; (notasi reader) -- Read notation (.gml) into a piece.
;;; See doc/design/03-reader.md.
;;;
;;; Slice 1: the public interface, &notasi-syntax-error, reading forms,
;;; dispatch, and the `piece` form.  Slice 2: scales, stroke sets and
;;; instruments.  Slice 3: parts and groups.  Slice 4: templates (`use').
;;; Only `text' (v2) raises `not-implemented'.

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

(define (raise-syntax-error kind line part step fmt args)
  "Raise a &notasi-syntax-error of KIND at LINE (1-based, or #f) in the
current source file, for PART and STEP (or #f), with a message built
from FMT and ARGS."
  (let ((file (current-source-file)))
    (raise-exception
     (make-exception
      (make-notasi-syntax-error kind file line part step)
      (make-exception-with-message
       (format #f "~a~@[:~a~]: ~?" (or file "<string>") line fmt args))))))

(define (syntax-error kind line fmt . args)
  "Raise a &notasi-syntax-error of KIND at LINE, not tied to a part."
  (raise-syntax-error kind line #f #f fmt args))

(define (part-error kind line part step fmt . args)
  "Raise a &notasi-syntax-error of KIND about PART at STEP (0-based, or
#f).  The message names the part and, when given, the step (1-based)."
  (raise-syntax-error kind line part step
                      (string-append "part `~a'~@[, step ~a~]: " fmt)
                      (cons* part (and step (1+ step)) args)))

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

(define (call-with-source-file path proc)
  "Call PROC with a port open on PATH.  The port is named PATH exactly,
so Guile's own read errors name the file as the user wrote it, not
relative to some %load-path entry."
  (call-with-input-file path
    (lambda (port)
      (set-port-filename! port path)
      (proc port))))

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

(define (positive-whole-number? x)
  (and (exact-integer? x) (positive? x)))

;;; The options a form accepts: (NAME VALID? . WHAT-IT-MUST-BE).
(define piece-options
  `((steps-per-pulse ,positive-whole-number? . "a positive whole number")
    (steps-per-system ,positive-whole-number? . "a positive whole number")))

(define group-options
  `((subtitle ,string? . "a string")))

(define (list-line datum fallback)
  "The 1-based line of DATUM if it is a list read with a position, else
FALLBACK.  Atoms carry no position."
  (match (and (pair? datum) (source-property datum 'line))
    ((? integer? line) (1+ line))
    (_ fallback)))

(define (parse-option option spec form-word form-line seen)
  "Check OPTION of a FORM-WORD form (\"piece\" or \"group\") against
SPEC, and return SEEN, an alist of options so far, with it added."
  (let ((line (list-line option form-line)))
    (match option
      (((? symbol? name) value)
       (match (assq name spec)
         (#f (syntax-error 'unknown-option line
                           "unknown ~a option `~a'" form-word name))
         ((_ valid? . what)
          (when (assq name seen)
            (syntax-error 'duplicate-option line
                          "option `~a' given twice" name))
          (unless (valid? value)
            (syntax-error 'bad-option line "`~a' must be ~a, not ~s"
                          name what value))
          (acons name value seen))))
      (_ (syntax-error 'bad-option line
                       "a ~a option must be (NAME VALUE), not ~s"
                       form-word option)))))

(define (parse-options options spec form-word form-line)
  (fold (lambda (option seen)
          (parse-option option spec form-word form-line seen))
        '() options))

(define (parse-piece-form form)
  "Build a piece with no parts from the `piece' form FORM, a (DATUM . LINE)."
  (match form
    ((('piece (? string? title) . options) . line)
     (let ((opts (parse-options options piece-options "piece" line)))
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
;;; Item 6: the shape of scale, strokes, instrument, part and group forms

(define definition-heads '(scale strokes instrument part group))

(define (split-group-body body)
  "Split the body of a group after its label into (PART-NAMES . OPTIONS):
the leading symbols, then the rest."
  (call-with-values (lambda () (span symbol? body)) cons))

(define (group-shape-ok? body)
  (match (split-group-body body)
    ((names . options)
     ;; Options are lists, so a stray string or number among the part
     ;; names is a bad form, not a bad option.
     (and (pair? names) (every pair? options)))))

(define (check-definition-shape form)
  (match form
    ((((or 'scale 'strokes) (? symbol?) _ ..1) . _) #t)
    ((('instrument (? symbol?) (? symbol?) (? symbol?) ..1) . _) #t)
    ((('part (? symbol?) (? symbol?) _ ..1) . _) #t)
    ((('group (? string?) . (? group-shape-ok?)) . _) #t)
    ((('scale . _) . line)
     (syntax-error 'bad-form line
                   "a scale needs a name and its degrees: (scale NAME DEGREE ...)"))
    ((('strokes . _) . line)
     (syntax-error 'bad-form line
                   "a stroke set needs a name and its strokes: (strokes NAME STROKE ...)"))
    ((('instrument . _) . line)
     (syntax-error 'bad-form line
                   "an instrument needs a name, a scale or stroke set, and its notes: (instrument NAME SCALE NOTE ...)"))
    ((('part . _) . line)
     (syntax-error 'bad-form line
                   "a part needs a name, an instrument and its music: (part NAME INSTRUMENT TOKEN ...)"))
    ((('group . _) . line)
     (syntax-error 'bad-form line
                   "a group needs a label and its parts, then any options: (group \"LABEL\" PART ... (subtitle \"TEXT\"))"))))

;;; ------------------------------------------------------------------
;;; Item 7: duplicate definitions.  Scales and stroke sets share one set
;;; of names, since an instrument refers to either; instruments and parts
;;; each have their own.  Groups are not named, so they have none.

(define (namespace head)
  (match head
    ((or 'scale 'strokes) 'scale)
    (other other)))

(define (check-duplicates definitions)
  (fold (lambda (form seen)
          (match form
            ((('group . _) . _) seen)
            (((head name . _) . line)
             (let ((key (cons (namespace head) name)))
               (when (member key seen)
                 (syntax-error 'duplicate-definition line
                               "`~a' is already defined in this file" name))
               (cons key seen)))))
        '()
        definitions))

;;; ------------------------------------------------------------------
;;; Item 5 (step 3): templates.  A definition is (FILE . FORM): the file
;;; it came from (#f for a string or port) and its (DATUM . LINE).

(define template-heads '(scale strokes instrument use))
(define merged-heads '(scale strokes instrument))

(define (definition-key form)
  (match form
    (((head name . _) . _) (cons (namespace head) name))))

(define (use-target form)
  "The template a `use' FORM names: a symbol or a string."
  (match form
    ((('use (and target (or (? symbol?) (? string?)))) . _) target)
    ((_ . line)
     (syntax-error 'bad-form line
                   "a use names one template: (use NAME) or (use \"file.gml\")"))))

(define (check-use-forms forms)
  "Item 5.1: every `use' in FORMS comes before the other forms (after
`piece'), then each names one template."
  (let loop ((forms forms) (after-other? #f))
    (match forms
      (() #t)
      ((form . rest)
       (match (form-head form)
         ('piece (loop rest after-other?))
         ('use
          (when after-other?
            (syntax-error 'use-not-first (cdr form)
                          "a use must come before the definitions, parts and groups"))
          (loop rest after-other?))
         (_ (loop rest #t))))))
  (for-each use-target (forms-with-heads forms '(use))))

(define (template-path target dir)
  "The file TARGET names, or #f if there is none.  A name is looked up
as templates/NAME.gml along %load-path; a string is relative to DIR."
  (match target
    ((? symbol?)
     (search-path %load-path
                  (string-append "templates/" (symbol->string target) ".gml")))
    ((? string?)
     ;; Inside the current directory, the path is the string itself, so
     ;; messages show `my-gamelan.gml', not `./my-gamelan.gml'.
     (let ((path (if (or (absolute-file-name? target) (string=? dir "."))
                     target
                     (in-vicinity dir target))))
       (and (file-exists? path)
            (not (file-is-directory? path))
            path)))))

(define (use-template form dir chain table)
  "Item 5.2: the definitions the template named by the `use' FORM makes
visible.  CHAIN holds the canonical paths being loaded; TABLE maps the
canonical path of each template already loaded to its definitions."
  (let* ((line (cdr form))
         (target (use-target form))
         (path (template-path target dir))
         (id (and path (canonicalize-path path))))
    (cond
     ((and id (member id chain))
      (syntax-error 'template-cycle line
                    "template ~s uses itself, through a cycle of uses" target))
     ((not path)
      (match target
        ((? symbol?)
         (syntax-error 'template-not-found line
                       "no template called `~a' (looked for templates/~a.gml)"
                       target target))
        (_ (syntax-error 'template-not-found line
                         "no template file ~s in ~a" target dir))))
     ((hash-ref table id))
     (else
      (let ((definitions (load-template path (cons id chain) table)))
        (hash-set! table id definitions)
        definitions)))))

(define (load-template path chain table)
  "Read the template at PATH and return the definitions it makes visible."
  (parameterize ((current-source-file path))
    (let ((forms (call-with-source-file path read-forms)))
      (for-each check-form forms)
      (match (find (lambda (form) (not (memq (form-head form) template-heads)))
                   forms)
        (#f #t)
        ((datum . line)
         (syntax-error 'not-in-template line
                       "a template holds only scale, strokes, instrument and use forms, not `~a'"
                       (car datum))))
      (file-definitions forms (dirname path) chain table))))

(define (own-keys forms)
  "The keys of the scales, stroke sets and instruments FORMS define."
  (filter-map (match-lambda
                ((((? symbol? head) (? symbol? name) . _) . _)
                 (and (memq head merged-heads)
                      (cons (namespace head) name)))
                (_ #f))
              forms))

(define (merge-templates lists keys)
  "Item 5.3: join the definitions in LISTS, one list per `use', in
order.  A definition reached twice keeps its first place; one whose key
is in KEYS (defined by the file itself) is dropped; any other name
defined twice is a `template-conflict'."
  (reverse
   (fold (lambda (definition merged)
           (let ((key (definition-key (cdr definition))))
             (cond
              ((memq definition merged) merged)
              ((member key keys) merged)
              ((find (lambda (other)
                       (equal? key (definition-key (cdr other))))
                     merged)
               => (lambda (first) (template-conflict definition first)))
              (else (cons definition merged)))))
         '()
         (concatenate lists))))

(define (template-conflict definition first)
  (match definition
    ((file . ((_ name . _) . line))
     (parameterize ((current-source-file file))
       (syntax-error 'template-conflict line
                     "`~a' is also defined in ~a; two templates used by one file can't define the same name"
                     name (or (car first) "<string>"))))))

(define (file-definitions forms dir chain table)
  "Items 5 to 7 for one file's FORMS: load its templates, check its own
definitions, and return the scales, stroke sets and instruments visible
from it, as definitions in merged order."
  (check-use-forms forms)
  (let* ((lists (map (lambda (form) (use-template form dir chain table))
                     (forms-with-heads forms '(use))))
         (merged (merge-templates lists (own-keys forms)))
         (definitions (forms-with-heads forms definition-heads)))
    (for-each check-definition-shape definitions)
    (check-duplicates definitions)
    (append merged
            (map (lambda (form) (cons (current-source-file) form))
                 (forms-with-heads forms merged-heads)))))

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
;;; Item 10: parts

(define (note-name-table instrument)
  "An alist from every way to write a note of INSTRUMENT to the note's
index: for a pitched note, each name and alias of its degree with the
octave (ding2, i2); for a stroke, each name and alias."
  (let ((degrees (list->vector (scale-degrees (instrument-scale instrument)))))
    (append-map
     (lambda (note i)
       (map (lambda (name)
              (cons (match (note-octave note)
                      (#f name)
                      (octave (symbol-append
                               name (string->symbol (number->string octave)))))
                    i))
            (degree-names (vector-ref degrees (note-degree note)))))
     (vector->list (instrument-notes instrument))
     (iota (vector-length (instrument-notes instrument))))))

(define (rest-token? token)
  (memq token '(- ·)))

(define (structural-token? token)
  "A token that marks time or layout rather than naming a note."
  (memq token '(_ - · /)))

(define (resolve-token-note token instrument table fail)
  "The 0-based index of the note TOKEN (a number or name) on INSTRUMENT.
FAIL is called with a kind and a message format and arguments."
  (let ((size (vector-length (instrument-notes instrument))))
    (match token
      ((? exact-integer? n)
       (unless (<= 1 n size)
         (fail 'note-out-of-range
               "note ~a does not exist on instrument `~a' (it has ~a notes)"
               n (instrument-name instrument) size))
       (1- n))
      ((? symbol? name)
       (match (assq name table)
         ((_ . i) i)
         (#f (fail 'unknown-note
                   (if (and (scale-pitched? (instrument-scale instrument))
                            (not (split-octave name)))
                       "`~a' is not a note of instrument `~a'; pitched notes need an octave number, e.g. ~a1"
                       "`~a' is not a note of instrument `~a'")
                   name (instrument-name instrument) name)))))))

(define (chord-member? x)
  (or (exact-integer? x)
      (and (symbol? x) (not (structural-token? x)))))

(define (resolve-chord members instrument table fail)
  "The sorted note indices of the chord MEMBERS."
  (unless (and (list? members) (>= (length members) 2)
               (every chord-member? members))
    (fail 'bad-chord
          "a chord needs two or more notes, each a number or a note name: ~s"
          members))
  (let ((notes (map (lambda (m) (resolve-token-note m instrument table fail))
                    members)))
    (unless (= (length notes) (length (delete-duplicates notes)))
      (fail 'bad-chord "a chord has the same note twice: ~s" members))
    (sort notes <)))

(define (read-tokens tokens instrument name line)
  "Turn the TOKENS of part NAME into events.  Return (EVENTS . STEPS)."
  (let ((table (note-name-table instrument)))
    (let loop ((tokens tokens)
               (step 0)
               (previous 'start)     ; start, note or rest
               (events '()))         ; (START DURATION NOTES), newest first
      (define (fail kind fmt . args)
        (apply part-error kind line name step fmt args))
      (define (strike notes)
        (loop (cdr tokens) (1+ step) 'note
              (cons (list step 1 notes) events)))
      (match tokens
        (()
         (cons (reverse-map (match-lambda
                              ((start duration notes)
                               (make-event start duration notes)))
                            events)
               step))
        ((token . rest)
         (match token
           ('/ (loop rest step previous events))
           ((? rest-token?) (loop rest (1+ step) 'rest events))
           ('_
            (match (cons previous events)
              (('note (start duration notes) . earlier)
               (loop rest (1+ step) 'note
                     (cons (list start (1+ duration) notes) earlier)))
              (_ (fail 'hold-without-note
                       (if (eq? previous 'start)
                           "a part cannot start with `_' (hold): there is no note to hold"
                           "`_' (hold) after a rest: there is no note to hold")))))
           ((or (? exact-integer?) (? symbol?))
            (strike (list (resolve-token-note token instrument table fail))))
           ((or (? pair?) ())               ; a chord, perhaps an empty one
            (strike (resolve-chord token instrument table fail)))
           (_ (fail 'unknown-token
                    "~s is not a note, a chord, `_', `-', `·' or `/'"
                    token))))))))

(define (reverse-map f lst)
  (fold (lambda (x acc) (cons (f x) acc)) '() lst))

(define (build-part form instruments)
  "Build a part record from FORM.  INSTRUMENTS is an alist from name to
instrument record.  Return (PART . STEPS), STEPS being its written
length."
  (match form
    ((('part name instrument-name . tokens) . line)
     (let ((instrument
            (or (assq-ref instruments instrument-name)
                (part-error 'undefined-instrument line name #f
                            "no instrument called `~a'" instrument-name))))
       (match (read-tokens tokens instrument name line)
         ((events . steps)
          (cons (make-part name instrument events (location line))
                steps)))))))

;;; ------------------------------------------------------------------
;;; Item 11: parts have equal length

(define (check-equal-lengths parts+steps)
  "PARTS+STEPS is a list of (PART . STEPS) in file order.  Return the
piece length: the common step count, or 0 with no parts."
  (match parts+steps
    (() 0)
    (((first . length) . others)
     (for-each
      (match-lambda
        ((part . steps)
         (unless (= steps length)
           (part-error 'unequal-length
                       (source-location-line (part-location part))
                       (part-name part) #f
                       "has ~a steps, but part `~a' has ~a; every part must have the same number of steps"
                       steps (part-name first) length))))
      others)
     length)))

;;; ------------------------------------------------------------------
;;; Item 12: groups

(define (check-one-pitched-instrument parts line)
  "Raise `mixed-pitched-group' if PARTS play more than one pitched
instrument (ADR 0011)."
  (match (filter (lambda (part)
                   (scale-pitched? (instrument-scale (part-instrument part))))
                 parts)
    (() #t)
    ((first . others)
     (let ((instrument (part-instrument first)))
       (match (find (lambda (part)
                      (not (eq? (part-instrument part) instrument)))
                    others)
         (#f #t)
         (part
          (part-error 'mixed-pitched-group line (part-name part) #f
                      "a group can hold one pitched instrument, but this one has `~a' and `~a'; put them in separate groups"
                      (instrument-name instrument)
                      (instrument-name (part-instrument part)))))))))

(define (build-group form parts used)
  "Build a group record from FORM.  PARTS is an alist from name to part;
USED lists the names of parts already in a group.  Return (GROUP . USED)
with this group's parts added to USED."
  (match form
    ((('group label . body) . line)
     (match (split-group-body body)
       ((names . options)
        (let* ((opts (parse-options options group-options "group" line))
               (used+parts
                (fold (lambda (name acc)
                        (match acc
                          ((used . members)
                           (let ((part (or (assq-ref parts name)
                                           (part-error 'undefined-part line name #f
                                                       "no part with this name"))))
                             (when (memq name used)
                               (part-error 'part-in-two-groups line name #f
                                           "is already in a group; a part can be in only one"))
                             (cons (cons name used) (cons part members))))))
                      (cons used '())
                      names))
               (members (reverse (cdr used+parts))))
          (check-one-pitched-instrument members line)
          (cons (make-group label (assq-ref opts 'subtitle) members
                            (location line))
                (car used+parts))))))))

(define (build-groups forms parts)
  "The written groups in FORMS and a default group for every other part
of PARTS (a list in file order), ordered by each group's first part in
the file."
  (let* ((by-name (map (lambda (part) (cons (part-name part) part)) parts))
         (written+used
          (fold (lambda (form acc)
                  (match acc
                    ((groups . used)
                     (match (build-group form by-name used)
                       ((group . used) (cons (cons group groups) used))))))
                (cons '() '())
                forms))
         (used (cdr written+used))
         (defaults (filter-map
                    (lambda (part)
                      (and (not (memq (part-name part) used))
                           (make-group (symbol->string (part-name part))
                                       #f (list part) #f)))
                    parts))
         (index (map cons (map part-name parts) (iota (length parts)))))
    (define (first-index group)
      (apply min (map (lambda (part) (assq-ref index (part-name part)))
                      (group-parts group))))
    (sort (append (reverse (car written+used)) defaults)
          (lambda (a b) (< (first-index a) (first-index b))))))

;;; ------------------------------------------------------------------
;;; Entry points

(define (read-piece forms dir chain)
  "Check FORMS, a list of (DATUM . LINE), and build the piece.  DIR is
where `(use \"file.gml\")' looks; CHAIN holds the canonical path of the
piece file, if any.  The checks run in the order given in 03-reader.md,
so a file with several problems always reports the same one."
  (define (named records name-of)
    (map (lambda (record) (cons (name-of record) record)) records))
  (define (build-each build definitions)
    ;; Each definition is built in the context of its own file, so its
    ;; locations and errors name that file.
    (map (match-lambda
           ((file . form)
            (parameterize ((current-source-file file))
              (build form))))
         definitions))
  (define (with-heads heads definitions)
    (filter (lambda (definition) (memq (form-head (cdr definition)) heads))
            definitions))
  (for-each check-form forms)
  (let* ((piece (parse-piece-form (find-piece-form forms)))
         (definitions (file-definitions forms dir chain (make-hash-table))))
    (let* ((scales (build-each build-scale
                               (with-heads '(scale strokes) definitions)))
           (instruments (build-each
                         (lambda (form)
                           (build-instrument form (named scales scale-name)))
                         (with-heads '(instrument) definitions)))
           (parts+steps (map (lambda (form)
                               (build-part form (named instruments
                                                       instrument-name)))
                             (forms-with-heads forms '(part))))
           (length (check-equal-lengths parts+steps))
           (parts (map car parts+steps))
           (groups (build-groups (forms-with-heads forms '(group)) parts)))
      (check-not-implemented forms '(text))   ; v2
      (make-piece (piece-title piece)
                  (piece-steps-per-pulse piece)
                  (piece-steps-per-system piece)
                  length scales instruments parts groups))))

(define (read-port port dir chain)
  (read-piece (read-forms port) dir chain))

(define* (read-piece-port port #:key directory)
  "Read a piece from PORT.  Raise a &notasi-syntax-error on any error.
DIRECTORY is where `(use \"file.gml\")' looks; it defaults to the
current directory."
  (read-port port (or directory (getcwd)) '()))

(define* (read-piece-string str #:key directory)
  "Read a piece from the string STR.  See `read-piece-port'."
  (call-with-input-string str
    (lambda (port) (read-piece-port port #:directory directory))))

(define (read-piece-file path)
  "Read a piece from the file at PATH.  Errors report PATH as their file."
  (parameterize ((current-source-file path))
    (call-with-source-file path
      (lambda (port)
        (read-port port (dirname path) (list (canonicalize-path path)))))))
