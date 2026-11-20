;;; Unit tests for (notasi reader), slices 1 to 4.
;;; Slice 1 (feat/reader-forms): the public interface, the
;;; &notasi-syntax-error condition, reading forms, dispatch, and the
;;; `piece` form with its options.
;;; Slice 2 (feat/reader-scales): the `scale`, `strokes` and
;;; `instrument` forms in a single file, their records, their error
;;; cases and the order in which the checks run.
;;; Slice 3 (feat/reader-parts): the `part` and `group` forms in a
;;; single file: events, parts, written and default groups, their
;;; error cases and the order in which the checks run.
;;; Slice 4 (feat/reader-templates): `use`, finding and merging
;;; templates, their error cases and check order, and tenzer1.nts.
;;;
;;; Written from doc/design/03-reader.md, 01-notation.md and 02-piece.md,
;;; not from the implementation. Tests check the error kind and the
;;; location fields, never the message text.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 exceptions)
             (ice-9 match)
             (notasi piece)
             (notasi reader))

;;; ------------------------------------------------------------------
;;; Helpers

(define (catch-syntax-error thunk)
  "Run THUNK. Return the condition it raises, or the symbol no-error
if it returns normally. Conditions that are not &notasi-syntax-error
are returned too, so a wrong condition type fails the kind checks."
  (guard (c (#t c))
    (thunk)
    'no-error))

(define (kind-of c)
  (if (notasi-syntax-error? c) (notasi-syntax-error-kind c) c))

(define (error-kind+line thunk)
  "Run THUNK and return (KIND LINE) of the &notasi-syntax-error it
raises, or the raised object (or no-error) unchanged."
  (let ((c (catch-syntax-error thunk)))
    (if (notasi-syntax-error? c)
        (list (notasi-syntax-error-kind c) (notasi-syntax-error-line c))
        c)))

(define (string-error str)
  "(KIND LINE) for reading STR with read-piece-string."
  (error-kind+line (lambda () (read-piece-string str))))

(define (string-kind str)
  "KIND only, for errors whose line the doc does not fix."
  (kind-of (catch-syntax-error (lambda () (read-piece-string str)))))

(define (lines . strs)
  "Join STRS with newlines, so line numbers in tests are easy to see."
  (string-join strs "\n"))

(define (valid-guile-line? line)
  (and (integer? line) (exact? line) (>= line 1)))

;;; Temporary files for read-piece-file.

(define tmp-dir
  (mkdtemp (string-append (or (getenv "TMPDIR") "/tmp") "/notasi-XXXXXX")))

(define tmp-files '())

(define (write-temp-file name contents)
  "Write CONTENTS to NAME inside tmp-dir and return its path."
  (let ((path (string-append tmp-dir "/" name)))
    (call-with-output-file path
      (lambda (port) (display contents port)))
    (set! tmp-files (cons path tmp-files))
    path))

(define (remove-temp-files)
  (for-each (lambda (f) (when (file-exists? f) (delete-file f))) tmp-files)
  (rmdir tmp-dir))

(test-begin "reader")

;;; ------------------------------------------------------------------
;;; Successful reads

(test-group "successful read"
  (let ((pc (read-piece-string "(piece \"Only a title\")")))
    (test-assert "returns a piece record" (piece? pc))
    (test-equal "title" "Only a title" (piece-title pc))
    (test-equal "default steps-per-pulse is 4" 4 (piece-steps-per-pulse pc))
    (test-equal "default steps-per-system is #f" #f
      (piece-steps-per-system pc))
    (test-equal "length is 0" 0 (piece-length pc))
    (test-equal "no scales" '() (piece-scales pc))
    (test-equal "no instruments" '() (piece-instruments pc))
    (test-equal "no parts" '() (piece-parts pc))
    (test-equal "no groups" '() (piece-groups pc)))

  (let ((pc (read-piece-string
             "(piece \"Kotekan\" (steps-per-pulse 2) (steps-per-system 16))")))
    (test-equal "given steps-per-pulse" 2 (piece-steps-per-pulse pc))
    (test-equal "given steps-per-system" 16 (piece-steps-per-system pc)))

  (let ((pc (read-piece-string
             "(piece \"Kotekan\" (steps-per-system 8) (steps-per-pulse 1))")))
    (test-equal "options in either order: steps-per-pulse" 1
      (piece-steps-per-pulse pc))
    (test-equal "options in either order: steps-per-system" 8
      (piece-steps-per-system pc)))

  (let ((pc (read-piece-string "(piece \"P\" (steps-per-pulse 1))")))
    (test-equal "steps-per-pulse alone: given" 1 (piece-steps-per-pulse pc))
    (test-equal "steps-per-pulse alone: steps-per-system default" #f
      (piece-steps-per-system pc)))

  (let ((pc (read-piece-string "(piece \"P\" (steps-per-system 32))")))
    (test-equal "steps-per-system alone: steps-per-pulse default" 4
      (piece-steps-per-pulse pc))
    (test-equal "steps-per-system alone: given" 32
      (piece-steps-per-system pc)))

  (let ((pc (read-piece-string "(piece \"P\" (steps-per-pulse 1) (steps-per-system 1))")))
    (test-equal "1 is a positive integer (steps-per-pulse)" 1
      (piece-steps-per-pulse pc))
    (test-equal "1 is a positive integer (steps-per-system)" 1
      (piece-steps-per-system pc))))

(test-group "comments and whitespace"
  (let ((pc (read-piece-string
             (lines ""
                    ";; A comment before the piece form"
                    "   "
                    "#| a block"
                    "   comment |#"
                    "\t(piece \"Commented\" ; trailing comment"
                    "   (steps-per-pulse 2))   "
                    ""
                    "; comment at the end"
                    ""))))
    (test-equal "title after comments" "Commented" (piece-title pc))
    (test-equal "option split over lines" 2 (piece-steps-per-pulse pc)))

  (test-equal "empty title string is a string" ""
    (piece-title (read-piece-string "(piece \"\")"))))

;;; ------------------------------------------------------------------
;;; The three entry points

(test-group "read-piece-string"
  (test-equal "#:directory is accepted" "D"
    (piece-title (read-piece-string "(piece \"D\")" #:directory tmp-dir)))
  (let ((c (catch-syntax-error (lambda () (read-piece-string "(foo)")))))
    (test-assert "raises a notasi-syntax-error" (notasi-syntax-error? c))
    (test-equal "file is #f" #f (notasi-syntax-error-file c))))

(test-group "read-piece-port"
  (let ((pc (call-with-input-string "(piece \"From a port\" (steps-per-pulse 3))"
              read-piece-port)))
    (test-equal "title" "From a port" (piece-title pc))
    (test-equal "steps-per-pulse" 3 (piece-steps-per-pulse pc)))
  (test-equal "#:directory is accepted" "D"
    (piece-title (call-with-input-string "(piece \"D\")"
                   (lambda (p) (read-piece-port p #:directory tmp-dir)))))
  (let ((c (catch-syntax-error
            (lambda ()
              (call-with-input-string (lines "(piece \"P\")" "" "(bogus)")
                read-piece-port)))))
    (test-assert "raises a notasi-syntax-error" (notasi-syntax-error? c))
    (test-equal "kind" 'unknown-form (kind-of c))
    (test-equal "file is #f for a string port" #f (notasi-syntax-error-file c))
    (test-equal "line" 3 (notasi-syntax-error-line c))))

(test-group "read-piece-file"
  (let* ((path (write-temp-file "ok.nts"
                                (lines ";; a piece" "(piece \"From a file\" (steps-per-system 12))" "")))
         (pc (read-piece-file path)))
    (test-equal "title" "From a file" (piece-title pc))
    (test-equal "steps-per-system" 12 (piece-steps-per-system pc))
    (test-equal "default steps-per-pulse" 4 (piece-steps-per-pulse pc))
    (test-equal "length 0" 0 (piece-length pc)))

  (let* ((path (write-temp-file "dup.nts"
                                (lines "(piece \"A\")" ";; again" "(piece \"B\")")))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "error kind" 'duplicate-piece (kind-of c))
    (test-equal "error file is the path given" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "error line" 3
      (and (notasi-syntax-error? c) (notasi-syntax-error-line c))))

  (let* ((path (write-temp-file "missing.nts" ";; nothing here\n"))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "missing-piece kind" 'missing-piece (kind-of c))
    (test-equal "missing-piece file is the path given" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "missing-piece line is #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-line c))))

  (let* ((path (write-temp-file "unbalanced.nts"
                                (lines "(piece \"P\")" "" "(part a b 1 2")))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "read-error kind" 'read-error (kind-of c))
    (test-equal "read-error file is the path given" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-assert "read-error line is an exact integer >= 1"
      (and (notasi-syntax-error? c)
           (valid-guile-line? (notasi-syntax-error-line c))))))

;;; ------------------------------------------------------------------
;;; The condition type

(test-group "condition type"
  (let ((c (catch-syntax-error
            (lambda () (read-piece-string (lines "(piece \"A\")" "(piece \"B\")"))))))
    (test-assert "notasi-syntax-error?" (notasi-syntax-error? c))
    (test-assert "is an &error" (error? c))
    (test-assert "carries a &message" (exception-with-message? c))
    (test-assert "message is a string" (string? (exception-message c)))
    (test-equal "kind is a symbol" 'duplicate-piece (notasi-syntax-error-kind c))
    (test-equal "file" #f (notasi-syntax-error-file c))
    (test-equal "line" 2 (notasi-syntax-error-line c))
    (test-equal "part is #f for a piece-form error" #f
      (notasi-syntax-error-part c))
    (test-equal "step is #f for a piece-form error" #f
      (notasi-syntax-error-step c)))
  (test-assert "predicate is #f for other conditions"
    (not (notasi-syntax-error?
          (make-exception (make-error) (make-exception-with-message "x")))))
  (test-assert "predicate is #f for non-conditions"
    (not (notasi-syntax-error? 'duplicate-piece))))

;;; ------------------------------------------------------------------
;;; Step 1: read errors

(test-group "read-error"
  (for-each
   (match-lambda
     ((name str)
      (let ((c (catch-syntax-error (lambda () (read-piece-string str)))))
        (test-equal (string-append name ": kind") 'read-error (kind-of c))
        (test-equal (string-append name ": file is #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
        (test-assert (string-append name ": line is an exact integer >= 1")
          (and (notasi-syntax-error? c)
               (valid-guile-line? (notasi-syntax-error-line c)))))))
   (list (list "missing close paren" "(piece \"P\"")
         (list "missing close paren on a later line"
               (lines "(piece \"P\")" "" "(part a b 1 2"))
         (list "extra close paren" (lines "(piece \"P\"))"))
         (list "dot dot" (lines "(piece \"P\")" "(part a b 1 . . 2)"))
         (list "unterminated string" "(piece \"P)")))

  (test-equal "read-error comes before missing-piece" 'read-error
    (string-kind (lines "(foo" "")))
  (test-equal "read-error comes before unknown-form" 'read-error
    (string-kind (lines "(foo)" "(piece \"P\")" "(bar")))
  (test-equal "read-error after a bad form still wins (all forms read first)"
    'read-error
    (string-kind (lines "(piece 42)" "(part a b 1 . 2)" "(")))
  (test-equal "read-error comes before improper-form" 'read-error
    (string-kind (lines "(piece \"P\")" "(part a b 1 . 2)" "(part a . . b)"))))

;;; ------------------------------------------------------------------
;;; Step 2: dispatch

(test-group "improper-form"
  (test-equal "lone dot in a part, line 3" '(improper-form 3)
    (string-error (lines "(piece \"P\")" "" "(part polos reyong 1 . 2)")))
  (test-equal "improper piece form, line 1" '(improper-form 1)
    (string-error "(piece \"P\" . 4)"))
  (test-equal "improper form before piece: improper-form, not piece-not-first"
    '(improper-form 1)
    (string-error (lines "(part a b 1 . 2)" "(piece \"P\")")))
  (test-equal "improper form with no piece: improper-form, not missing-piece"
    '(improper-form 2)
    (string-error (lines ";; no piece" "(part a b 1 . 2)")))
  (test-equal "improper form comes before bad-title" '(improper-form 2)
    (string-error (lines "(piece 1)" "(text . \"x\")"))))

(test-group "unknown-form"
  (test-equal "unknown head, line 1" '(unknown-form 1)
    (string-error (lines "(foo 1 2)" "(piece \"P\")")))
  (test-equal "unknown head after piece, line 3" '(unknown-form 3)
    (string-error (lines "(piece \"P\")" "" "(foo 1 2)")))
  (test-equal "head is case-sensitive" '(unknown-form 2)
    (string-error (lines "(piece \"P\")" "(Part a b 1)")))
  (test-equal "head is a string, not a symbol" '(unknown-form 2)
    (string-error (lines "(piece \"P\")" "(\"part\" a b 1)")))
  (test-equal "head is a number" '(unknown-form 2)
    (string-error (lines "(piece \"P\")" "(42 a b)")))
  (test-equal "head is a list" '(unknown-form 2)
    (string-error (lines "(piece \"P\")" "((part) a b)")))
  ;; Atoms carry no source position, so only the kind is checked.
  (test-equal "top-level symbol" 'unknown-form
    (string-kind (lines "(piece \"P\")" "foo")))
  (test-equal "top-level number" 'unknown-form
    (string-kind (lines "(piece \"P\")" "42")))
  (test-equal "top-level string" 'unknown-form
    (string-kind (lines "(piece \"P\")" "\"hello\"")))
  (test-equal "top-level empty list" 'unknown-form
    (string-kind (lines "(piece \"P\")" "()")))
  (test-equal "top-level vector" 'unknown-form
    (string-kind (lines "(piece \"P\")" "#(1 2)")))
  (test-equal "unknown form before missing piece: unknown-form" '(unknown-form 2)
    (string-error (lines ";; no piece" "(foo)")))
  (test-equal "unknown form after a misplaced piece: unknown-form, not piece-not-first"
    '(unknown-form 3)
    (string-error (lines "(text \"x\")" "(piece \"P\")" "(foo)")))
  (test-equal "unknown form after a duplicate piece: unknown-form" '(unknown-form 3)
    (string-error (lines "(piece \"A\")" "(piece \"B\")" "(foo)")))
  (test-equal "unknown form after a bad title: unknown-form" '(unknown-form 2)
    (string-error (lines "(piece 1)" "(foo)")))
  (test-equal "unknown form after a bad option: unknown-form" '(unknown-form 4)
    (string-error (lines "(piece \"P\" (steps-per-pulse 0))" "" "" "(foo)")))
  (test-equal "first bad form in file order wins: improper then unknown"
    '(improper-form 2)
    (string-error (lines "(piece \"P\")" "(part a b 1 . 2)" "(foo)")))
  (test-equal "first bad form in file order wins: unknown then improper"
    '(unknown-form 2)
    (string-error (lines "(piece \"P\")" "(foo)" "(part a b 1 . 2)"))))

;;; ------------------------------------------------------------------
;;; Step 3: the piece form is present, first and only once

(test-group "missing-piece"
  (test-equal "empty string" '(missing-piece #f) (string-error ""))
  (test-equal "only whitespace and comments" '(missing-piece #f)
    (string-error (lines "  " ";; comment" "#| block |#" "")))
  (test-equal "only not-yet-implemented forms: missing-piece, not not-implemented"
    '(missing-piece #f)
    (string-error (lines "(scale selisir ding dong)" "(text \"x\")"))))

(test-group "piece-not-first"
  (test-equal "use before piece" '(piece-not-first 1)
    (string-error (lines "(use gong-kebyar)" "(piece \"P\")")))
  (test-equal "scale before piece, after comments" '(piece-not-first 3)
    (string-error (lines ";; c" "" "(scale selisir ding)" "(piece \"P\")")))
  (test-equal "piece-not-first comes before bad-title" '(piece-not-first 1)
    (string-error (lines "(text \"x\")" "(piece 1)"))))

(test-group "duplicate-piece"
  (test-equal "second piece on line 2" '(duplicate-piece 2)
    (string-error (lines "(piece \"A\")" "(piece \"B\")")))
  (test-equal "second piece on line 4" '(duplicate-piece 4)
    (string-error (lines "(piece \"A\")" "" ";; again" "(piece \"B\")")))
  (test-equal "identical duplicate is still a duplicate" '(duplicate-piece 2)
    (string-error (lines "(piece \"A\")" "(piece \"A\")")))
  (test-equal "duplicate-piece comes before bad-title" '(duplicate-piece 2)
    (string-error (lines "(piece 1)" "(piece 2)")))
  (test-equal "duplicate-piece comes before bad-option" '(duplicate-piece 2)
    (string-error (lines "(piece \"A\" (steps-per-pulse 0))" "(piece \"B\")")))
  (test-equal "duplicate-piece comes before not-implemented" '(duplicate-piece 3)
    (string-error (lines "(piece \"A\")" "(text \"x\")" "(piece \"B\")"))))

;;; ------------------------------------------------------------------
;;; Step 4: title and options. The piece form is the form to blame, so
;;; the line is the piece form's line (options are on the same line).

(test-group "bad-title"
  (test-equal "title is a symbol" '(bad-title 1) (string-error "(piece title)"))
  (test-equal "title is a number" '(bad-title 1) (string-error "(piece 42)"))
  (test-equal "title is missing" '(bad-title 1) (string-error "(piece)"))
  (test-equal "title missing, option in its place" '(bad-title 1)
    (string-error "(piece (steps-per-pulse 4))"))
  (test-equal "title is a list" '(bad-title 1)
    (string-error "(piece (\"P\"))"))
  (test-equal "bad title on line 3" '(bad-title 3)
    (string-error (lines ";; c" "" "(piece #t)")))
  (test-equal "bad-title comes before bad-option" '(bad-title 1)
    (string-error "(piece 1 (steps-per-pulse 0))"))
  (test-equal "bad-title comes before unknown-option" '(bad-title 1)
    (string-error "(piece 1 (tempo 60))"))
  (test-equal "bad-title comes before not-implemented" '(bad-title 1)
    (string-error (lines "(piece 1)" "(text \"x\")"))))

(test-group "bad-option"
  (for-each
   (match-lambda
     ((name str)
      (test-equal name '(bad-option 1) (string-error str))))
   (list (list "option is a bare symbol" "(piece \"P\" steps-per-pulse)")
         (list "option is a number" "(piece \"P\" 4)")
         (list "option is a string" "(piece \"P\" \"subtitle\")")
         (list "option has no value" "(piece \"P\" (steps-per-pulse))")
         (list "option has two values" "(piece \"P\" (steps-per-pulse 4 8))")
         (list "steps-per-pulse 0" "(piece \"P\" (steps-per-pulse 0))")
         (list "steps-per-pulse negative" "(piece \"P\" (steps-per-pulse -4))")
         (list "steps-per-pulse fraction" "(piece \"P\" (steps-per-pulse 1/2))")
         (list "steps-per-pulse non-integer real" "(piece \"P\" (steps-per-pulse 2.5))")
         (list "steps-per-pulse string" "(piece \"P\" (steps-per-pulse \"4\"))")
         (list "steps-per-pulse symbol" "(piece \"P\" (steps-per-pulse four))")
         (list "steps-per-system 0" "(piece \"P\" (steps-per-system 0))")
         (list "steps-per-system negative" "(piece \"P\" (steps-per-system -16))")
         (list "steps-per-system string" "(piece \"P\" (steps-per-system \"16\"))")
         (list "steps-per-system list" "(piece \"P\" (steps-per-system (16)))")))
  (test-equal "bad option on line 2" '(bad-option 2)
    (string-error (lines ";; c" "(piece \"P\" (steps-per-pulse 0))")))
  (test-equal "bad option after a good one" '(bad-option 1)
    (string-error "(piece \"P\" (steps-per-pulse 4) (steps-per-system 0))"))
  (test-equal "bad-option comes before not-implemented" '(bad-option 1)
    (string-error (lines "(piece \"P\" (steps-per-pulse 0))" "(text \"x\")"))))

(test-group "unknown-option"
  (test-equal "unknown option name" '(unknown-option 1)
    (string-error "(piece \"P\" (tempo 60))"))
  (test-equal "option names are case-sensitive" '(unknown-option 1)
    (string-error "(piece \"P\" (Steps-Per-Pulse 4))"))
  (test-equal "unknown option after good ones" '(unknown-option 1)
    (string-error "(piece \"P\" (steps-per-pulse 4) (steps-per-system 8) (tempo 60))"))
  (test-equal "unknown option on line 3" '(unknown-option 3)
    (string-error (lines "" "" "(piece \"P\" (subtitle \"x\"))")))
  (test-equal "unknown-option comes before not-implemented" '(unknown-option 1)
    (string-error (lines "(piece \"P\" (tempo 60))" "(text \"x\")"))))

(test-group "duplicate-option"
  (test-equal "steps-per-pulse twice" '(duplicate-option 1)
    (string-error "(piece \"P\" (steps-per-pulse 4) (steps-per-pulse 2))"))
  (test-equal "steps-per-pulse twice with the same value" '(duplicate-option 1)
    (string-error "(piece \"P\" (steps-per-pulse 4) (steps-per-pulse 4))"))
  (test-equal "steps-per-system twice, not adjacent" '(duplicate-option 1)
    (string-error
     "(piece \"P\" (steps-per-system 8) (steps-per-pulse 4) (steps-per-system 16))"))
  (test-equal "duplicate option on line 2" '(duplicate-option 2)
    (string-error (lines ";; c" "(piece \"P\" (steps-per-pulse 4) (steps-per-pulse 2))")))
  (test-equal "duplicate-option comes before not-implemented" '(duplicate-option 1)
    (string-error (lines "(piece \"P\" (steps-per-pulse 4) (steps-per-pulse 4))"
                         "(text \"x\")"))))

;;; ------------------------------------------------------------------
;;; Step 5 (later slices): every other known form is not implemented

(test-group "not-implemented"
  (for-each
   (match-lambda
     ((head form)
      (test-equal (string-append head ": not-implemented at its own line")
        '(not-implemented 3)
        (string-error (lines "(piece \"P\")" ";; next" form)))))
   (list (list "text" "(text \"A note\")")))
  (test-equal "line 2" '(not-implemented 2)
    (string-error (lines "(piece \"P\")" "(text \"x\")")))
  (test-equal "first not-implemented form in file order" '(not-implemented 4)
    (string-error (lines "(piece \"P\")" "" "" "(text \"first\")" "(text \"x\")")))
  (let ((c (catch-syntax-error
            (lambda () (read-piece-string (lines "(piece \"P\")" "(text \"x\")"))))))
    (test-equal "not-implemented: file #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "not-implemented: part field #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-part c)))
    (test-equal "not-implemented: step field #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-step c))))
  (let* ((path (write-temp-file "text.nts" (lines "(piece \"P\")" "(text \"x\")")))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "not-implemented from a file: kind" 'not-implemented (kind-of c))
    (test-equal "not-implemented from a file: file" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "not-implemented from a file: line" 2
      (and (notasi-syntax-error? c) (notasi-syntax-error-line c)))))

;;; ==================================================================
;;; Slice 2: scale, strokes and instrument forms
;;; ==================================================================

;;; ------------------------------------------------------------------
;;; Helpers for slice 2

(define (try-read thunk)
  "Run THUNK and return the piece it reads, or #f if it raises. A test
that then takes a field of #f fails with an error instead of stopping
the whole file."
  (guard (c (#t #f)) (thunk)))

(define (try-read-string . strs)
  "Read the lines STRS as a piece, or #f if reading raises."
  (try-read (lambda () (read-piece-string (apply lines strs)))))

(define (find-named name-of name lst)
  "The element of LST whose NAME-OF is NAME. Raises if there is none,
so a test using it fails rather than passing on #f."
  (or (find (lambda (x) (eq? (name-of x) name)) lst)
      (error "not found:" name)))

(define (scale-named pc name) (find-named scale-name name (piece-scales pc)))
(define (instrument-named pc name)
  (find-named instrument-name name (piece-instruments pc)))

(define (note-fields n)
  "A note as (NAME DEGREE OCTAVE)."
  (list (note-name n) (note-degree n) (note-octave n)))

(define (instrument-note-fields inst)
  (map note-fields (vector->list (instrument-notes inst))))

(define (location-line x)
  (source-location-line
   (cond ((scale? x) (scale-location x))
         ((degree? x) (degree-location x))
         ((instrument? x) (instrument-location x))
         (else (error "no location:" x)))))

(define (location-file x)
  (source-location-file
   (cond ((scale? x) (scale-location x))
         ((degree? x) (degree-location x))
         ((instrument? x) (instrument-location x))
         (else (error "no location:" x)))))

;;; The main fixture. Line numbers matter: the comments give them.
(define defs-text
  (lines "(piece \"Definitions\")"                          ; 1
         "(strokes gong-strokes G P)"                       ; 2
         "(scale selisir"                                   ; 3
         "  (ding (alias i) (display \"i\"))"               ; 4
         "  dong"                                           ; 5
         "  (deng (alias e ee))"                            ; 6
         "  dung (dang (display \"•\")))"                   ; 7
         "(strokes kendang-strokes (dag (alias D) (display \"D\")) dug)" ; 8
         "(instrument ugal selisir i1 dong1 e1 dung1 dang1 ding2)" ; 9
         "(instrument gong gong-strokes P G)"               ; 10
         "(instrument kendang"                              ; 11
         "  kendang-strokes D dug)"                         ; 12
         ""))

;;; ------------------------------------------------------------------
;;; Successful reads

(test-group "scales and stroke sets"
  (let ((pc (try-read-string defs-text)))
    (test-assert "reads into a piece" (piece? pc))
    (test-equal "scales and stroke sets together, in file order"
      '(gong-strokes selisir kendang-strokes)
      (map scale-name (piece-scales pc)))
    (test-equal "pitched? is #t for scale, #f for strokes"
      '(#f #t #f)
      (map scale-pitched? (piece-scales pc)))
    (test-equal "degree names in order"
      '(ding dong deng dung dang)
      (map degree-name (scale-degrees (scale-named pc 'selisir))))
    (test-equal "aliases: a list, empty by default"
      '((i) () (e ee) () ())
      (map degree-aliases (scale-degrees (scale-named pc 'selisir))))
    (test-equal "display: given, or the name as a string; Unicode works"
      '("i" "dong" "deng" "dung" "•")
      (map degree-display (scale-degrees (scale-named pc 'selisir))))
    (test-equal "stroke names in order"
      '(G P)
      (map degree-name (scale-degrees (scale-named pc 'gong-strokes))))
    (test-equal "stroke defaults: no aliases, display is the name"
      '((() "G") (() "P"))
      (map (lambda (d) (list (degree-aliases d) (degree-display d)))
           (scale-degrees (scale-named pc 'gong-strokes))))
    (test-equal "stroke with alias and display"
      '((dag (D) "D") (dug () "dug"))
      (map (lambda (d) (list (degree-name d) (degree-aliases d)
                             (degree-display d)))
           (scale-degrees (scale-named pc 'kendang-strokes))))
    (test-equal "scale lines" '(2 3 8)
      (map location-line (piece-scales pc)))
    (test-equal "degree lines: own line for a list, scale's line for a bare name"
      '(4 3 6 3 7)
      (map location-line (scale-degrees (scale-named pc 'selisir))))
    (test-equal "stroke lines: bare strokes use the stroke set's line" '(2 2)
      (map location-line (scale-degrees (scale-named pc 'gong-strokes))))
    (test-equal "files are #f when read from a string"
      '(#f #f #f #f #f #f #f #f)
      (append (map location-file (piece-scales pc))
              (map location-file (scale-degrees (scale-named pc 'selisir)))))
    (test-assert "locations are source-location records"
      (every (lambda (d) (source-location? (degree-location d)))
             (scale-degrees (scale-named pc 'selisir)))))

  (let ((pc (try-read-string "(piece \"P\")" "(scale s (ding))")))
    (test-equal "(NAME) with no options: defaults" '(ding () "ding")
      (let ((d (car (scale-degrees (scale-named pc 's)))))
        (list (degree-name d) (degree-aliases d) (degree-display d)))))

  (let ((pc (try-read-string "(piece \"P\")" "(strokes s (k1 (alias k2 kk)) k3)")))
    (test-equal "stroke names and aliases may end in a digit"
      '((k1 (k2 kk)) (k3 ()))
      (map (lambda (d) (list (degree-name d) (degree-aliases d)))
           (scale-degrees (scale-named pc 's))))))

(test-group "instruments"
  (let ((pc (try-read-string defs-text)))
    (test-equal "instruments in file order" '(ugal gong kendang)
      (map instrument-name (piece-instruments pc)))
    (test-equal "instrument lines" '(9 10 11)
      (map location-line (piece-instruments pc)))
    (test-equal "instrument files are #f from a string" '(#f #f #f)
      (map location-file (piece-instruments pc)))
    (test-assert "instrument scale is the scale record in piece-scales"
      (eq? (instrument-scale (instrument-named pc 'ugal))
           (scale-named pc 'selisir)))
    (test-assert "instrument stroke set is the record in piece-scales"
      (eq? (instrument-scale (instrument-named pc 'gong))
           (scale-named pc 'gong-strokes)))
    (test-assert "notes is a vector"
      (vector? (instrument-notes (instrument-named pc 'ugal))))
    (test-equal "pitched notes: canonical name, degree index, octave"
      '((ding1 0 1) (dong1 1 1) (deng1 2 1) (dung1 3 1) (dang1 4 1) (ding2 0 2))
      (instrument-note-fields (instrument-named pc 'ugal)))
    (test-equal "stroke notes in the instrument's order, octave #f"
      '((P 1 #f) (G 0 #f))
      (instrument-note-fields (instrument-named pc 'gong)))
    (test-equal "stroke notes given by alias are stored by name"
      '((dag 0 #f) (dug 1 #f))
      (instrument-note-fields (instrument-named pc 'kendang)))
    (test-equal "length 0" 0 (piece-length pc))
    (test-equal "no parts" '() (piece-parts pc))
    (test-equal "no groups" '() (piece-groups pc))
    (test-equal "title" "Definitions" (piece-title pc)))

  (let ((pc (try-read-string "(piece \"P\")"
                             "(scale s ding dong)"
                             "(instrument x s ding0 dong0 ding1)")))
    (test-equal "octave 0 is allowed and below octave 1"
      '((ding0 0 0) (dong0 1 0) (ding1 0 1))
      (instrument-note-fields (instrument-named pc 'x))))

  (let ((pc (try-read-string "(piece \"P\")"
                             "(scale s ding dong)"
                             "(instrument x s dong9 ding10 dong10 ding12)")))
    (test-equal "multi-digit octaves, compared as numbers"
      '((dong9 1 9) (ding10 0 10) (dong10 1 10) (ding12 0 12))
      (instrument-note-fields (instrument-named pc 'x))))

  (let ((pc (try-read-string "(piece \"P\")"
                             "(strokes s k1 (k2 (alias k22)) k3)"
                             "(instrument x s k3 k22 k1)")))
    (test-equal "strokes ending in a digit, any order, alias resolved"
      '((k3 2 #f) (k2 1 #f) (k1 0 #f))
      (instrument-note-fields (instrument-named pc 'x))))

  (let ((pc (try-read-string "(piece \"P\")"
                             "(instrument ugal selisir a1 ding2)"
                             "(instrument gong gong G)"
                             "(strokes gong G)"
                             "(scale selisir ding (dang (alias a)))")))
    (test-equal "instrument before its scale: scales in file order"
      '(gong selisir)
      (map scale-name (piece-scales pc)))
    (test-equal "instrument before its scale: instruments in file order"
      '(ugal gong)
      (map instrument-name (piece-instruments pc)))
    (test-equal "instrument before its scale: notes resolved"
      '((dang1 1 1) (ding2 0 2))
      (instrument-note-fields (instrument-named pc 'ugal)))
    (test-assert "instrument may share a name with a stroke set"
      (eq? (instrument-scale (instrument-named pc 'gong))
           (scale-named pc 'gong))))

  (let ((pc (try-read-string "(piece \"P\")"
                             "(scale s (ding (alias i) (display \"i\")) dong)"
                             "(strokes k (dag (display \"D\")) G)"
                             "(instrument x s i1 dong1 i2)"
                             "(instrument y k G dag)")))
    (test-equal "note-display on a read instrument" '("i" "dong" "i")
      (let ((inst (instrument-named pc 'x)))
        (map (lambda (n) (note-display inst n))
             (vector->list (instrument-notes inst)))))
    (test-equal "note-label on a read instrument" '("i1" "dong1" "i2")
      (let ((inst (instrument-named pc 'x)))
        (map (lambda (n) (note-label inst n))
             (vector->list (instrument-notes inst)))))
    (test-equal "note-label for strokes is the display" '("G" "D")
      (let ((inst (instrument-named pc 'y)))
        (map (lambda (n) (note-label inst n))
             (vector->list (instrument-notes inst)))))))

(test-group "definitions read from a file"
  (let* ((path (write-temp-file "defs.nts" defs-text))
         (pc (try-read (lambda () (read-piece-file path)))))
    (test-assert "reads into a piece" (piece? pc))
    (test-equal "scale files are the path given" (list path path path)
      (map location-file (piece-scales pc)))
    (test-equal "degree files are the path given"
      (list path path path path path)
      (map location-file (scale-degrees (scale-named pc 'selisir))))
    (test-equal "degree lines from a file" '(4 3 6 3 7)
      (map location-line (scale-degrees (scale-named pc 'selisir))))
    (test-equal "instrument files are the path given" (list path path path)
      (map location-file (piece-instruments pc)))
    (test-equal "instrument lines from a file" '(9 10 11)
      (map location-line (piece-instruments pc)))))

(test-group "definitions read from a port"
  (let ((pc (try-read (lambda ()
                        (call-with-input-string defs-text read-piece-port)))))
    (test-equal "instruments" '(ugal gong kendang)
      (map instrument-name (piece-instruments pc)))
    (test-equal "files are #f from a port" '(#f #f #f)
      (map location-file (piece-scales pc)))))

;;; The contents of templates/selisir.nts (before it had display forms)
;;; and templates/gong-kebyar.nts (without its `use`), pasted into one
;;; file.
(test-group "gong kebyar definitions"
  (let ((pc (try-read-string
             "(piece \"Gong kebyar\" (steps-per-pulse 1))"
             ";; Selisir: the five-tone pelog scale of Balinese gong kebyar."
             ";; Degrees can be written by name (ding) or by vowel (i)."
             ""
             "(scale selisir"
             "  (ding (alias i))"
             "  (dong (alias o))"
             "  (deng (alias e))"
             "  (dung (alias u))"
             "  (dang (alias a)))"
             ""
             "(strokes kempli-strokes  K)"
             "(strokes gong-strokes"
             "  G                                           ; gong"
             "  P)                                          ; kempur"
             "(strokes kendang-strokes  dag dug du)"
             ""
             ";; Ugal: 10 keys, o1 (dong1) to i3 (ding3), an octave below the pemade."
             "(instrument ugal    selisir  o1 e1 u1 a1 i2 o2 e2 u2 a2 i3)"
             ""
             ";; Reyong: 12 pots, e1 (deng1) to u3 (dung3)."
             "(instrument reyong  selisir  e1 u1 a1 i2 o2 e2 u2 a2 i3 o3 e3 u3)"
             ""
             "(instrument kempli  kempli-strokes   K)"
             "(instrument gong    gong-strokes     G P)"
             "(instrument kendang kendang-strokes  dag dug du)"
             "")))
    (test-equal "scales" '(selisir kempli-strokes gong-strokes kendang-strokes)
      (map scale-name (piece-scales pc)))
    (test-equal "scale lines" '(5 12 13 16)
      (map location-line (piece-scales pc)))
    (test-equal "selisir degree lines" '(6 7 8 9 10)
      (map location-line (scale-degrees (scale-named pc 'selisir))))
    (test-equal "selisir displays default to names"
      '("ding" "dong" "deng" "dung" "dang")
      (map degree-display (scale-degrees (scale-named pc 'selisir))))
    (test-equal "instruments" '(ugal reyong kempli gong kendang)
      (map instrument-name (piece-instruments pc)))
    (test-equal "instrument lines" '(19 22 24 25 26)
      (map location-line (piece-instruments pc)))
    (test-equal "ugal notes"
      '((dong1 1 1) (deng1 2 1) (dung1 3 1) (dang1 4 1)
        (ding2 0 2) (dong2 1 2) (deng2 2 2) (dung2 3 2) (dang2 4 2)
        (ding3 0 3))
      (instrument-note-fields (instrument-named pc 'ugal)))
    (test-equal "reyong has 12 notes, deng1 to dung3"
      '(12 deng1 dung3)
      (let ((v (instrument-notes (instrument-named pc 'reyong))))
        (list (vector-length v)
              (note-name (vector-ref v 0))
              (note-name (vector-ref v 11)))))
    (test-equal "kendang notes" '((dag 0 #f) (dug 1 #f) (du 2 #f))
      (instrument-note-fields (instrument-named pc 'kendang)))
    (test-equal "reyong lane labels use the default display"
      '("deng1" "dung3")
      (let* ((inst (instrument-named pc 'reyong))
             (v (instrument-notes inst)))
        (list (note-label inst (vector-ref v 0))
              (note-label inst (vector-ref v 11)))))
    (test-equal "length 0, no parts, no groups" '(0 () ())
      (list (piece-length pc) (piece-parts pc) (piece-groups pc)))))

;;; ------------------------------------------------------------------
;;; Error cases (slice 2). Each checks (KIND LINE).

(define (table-tests expected-kind cases)
  "CASES is a list of (NAME LINE STRING). Check each reads to
(EXPECTED-KIND LINE)."
  (for-each
   (match-lambda
     ((name line str)
      (test-equal name (list expected-kind line) (string-error str))))
   cases))

(test-group "bad-form"
  (table-tests 'bad-form
   (list (list "scale with no name" 2 (lines "(piece \"P\")" "(scale)"))
         (list "scale name is a string" 2
               (lines "(piece \"P\")" "(scale \"selisir\" ding dong)"))
         (list "scale name is a number" 2
               (lines "(piece \"P\")" "(scale 5 ding dong)"))
         (list "scale name is a list" 2
               (lines "(piece \"P\")" "(scale (selisir) ding dong)"))
         (list "scale with no degrees" 2
               (lines "(piece \"P\")" "(scale selisir)"))
         (list "strokes with no name" 2 (lines "(piece \"P\")" "(strokes)"))
         (list "strokes name is a string" 2
               (lines "(piece \"P\")" "(strokes \"gong\" G)"))
         (list "strokes with no strokes" 2
               (lines "(piece \"P\")" "(strokes gong)"))
         (list "instrument with no name" 2
               (lines "(piece \"P\")" "(instrument)"))
         (list "instrument name is a string" 3
               (lines "(piece \"P\")" "(strokes g G)"
                      "(instrument \"gong\" g G)"))
         (list "instrument name is a number" 3
               (lines "(piece \"P\")" "(strokes g G)" "(instrument 1 g G)"))
         (list "instrument with a name only" 3
               (lines "(piece \"P\")" "(strokes g G)" "(instrument gong)"))
         (list "instrument with no notes" 3
               (lines "(piece \"P\")" "(strokes g G)" "(instrument gong g)"))
         (list "bad form on line 4 after comments" 4
               (lines "(piece \"P\")" ";; c" "" "(scale selisir)"))
         (list "first bad form in file order" 3
               (lines "(piece \"P\")" "(scale s ding)" "(instrument x s)"
                      "(scale)")))))

(test-group "duplicate-definition"
  (table-tests 'duplicate-definition
   (list (list "scale / scale" 3
               (lines "(piece \"P\")" "(scale s ding)" "(scale s dong)"))
         (list "identical scales are still duplicates" 3
               (lines "(piece \"P\")" "(scale s ding)" "(scale s ding)"))
         (list "strokes / strokes" 4
               (lines "(piece \"P\")" "(strokes g G)" "" "(strokes g P)"))
         (list "instrument / instrument" 4
               (lines "(piece \"P\")" "(strokes g G P)" "(instrument x g G)"
                      "(instrument x g P)"))
         (list "scale / strokes" 3
               (lines "(piece \"P\")" "(scale g ding)" "(strokes g G)"))
         (list "strokes / scale" 3
               (lines "(piece \"P\")" "(strokes g G)" "(scale g ding)"))
         (list "three definitions: the second is reported" 3
               (lines "(piece \"P\")" "(scale s ding)" "(scale s dong)"
                      "(scale s deng)"))
         (list "first duplicate in file order" 4
               (lines "(piece \"P\")" "(scale b ding)" "(scale a ding)"
                      "(scale a dong)" "(scale b dong)"))))
  (let ((pc (try-read-string "(piece \"P\")" "(strokes gong G)"
                             "(instrument gong gong G)")))
    (test-equal "an instrument may share a name with a stroke set" '(gong)
      (map instrument-name (piece-instruments pc))))
  (let ((pc (try-read-string "(piece \"P\")" "(scale ugal ding)"
                             "(instrument ugal ugal ding1)")))
    (test-equal "an instrument may share a name with a scale" '(ugal)
      (map instrument-name (piece-instruments pc)))))

(test-group "bad-degree"
  ;; Each case is (NAME LINE STRING). A degree written as a list
  ;; reports its own line; a bare degree reports its scale's line.
  (table-tests 'bad-degree
   (list (list "bare degree is a number: scale's line" 2
               (lines "(piece \"P\")" "(scale s ding" "  42)"))
         (list "bare degree is a string: scale's line" 2
               (lines "(piece \"P\")" "(scale s ding" "  \"dong\")"))
         (list "degree list with a string head: its own line" 3
               (lines "(piece \"P\")" "(scale s ding" "  (\"dong\" (alias o)))"))
         (list "degree list with a number head" 3
               (lines "(piece \"P\")" "(scale s ding" "  (5 (alias o)))"))
         (list "empty list as a degree" 2
               (lines "(piece \"P\")" "(scale s ding ())"))
         (list "option is a bare symbol" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong alias))"))
         (list "option is a string" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong \"o\"))"))
         (list "unknown option" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (colour red)))"))
         (list "option name is case-sensitive" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (Alias o)))"))
         (list "display is a symbol" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (display o)))"))
         (list "display is a number" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (display 5)))"))
         (list "display with no value" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (display)))"))
         (list "display with two strings" 3
               (lines "(piece \"P\")" "(scale s ding"
                      "  (dong (display \"o\" \"O\")))"))
         (list "(alias) with no names" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (alias)))"))
         (list "alias given twice" 3
               (lines "(piece \"P\")" "(scale s ding"
                      "  (dong (alias o) (alias oo)))"))
         (list "display given twice" 3
               (lines "(piece \"P\")" "(scale s ding"
                      "  (dong (display \"o\") (display \"o\")))"))
         (list "stroke: unknown option" 3
               (lines "(piece \"P\")" "(strokes k G" "  (dag (colour red)))"))
         (list "stroke: display not a string" 2
               (lines "(piece \"P\")" "(strokes k G (dag (display D)))"))
         (list "stroke: bare number" 2
               (lines "(piece \"P\")" "(strokes k G" "  1)"))
         (list "stroke: (alias) with no names" 3
               (lines "(piece \"P\")" "(strokes k G" "  (dag (alias)))"))
         (list "first bad degree in order within a scale" 3
               (lines "(piece \"P\")" "(scale s ding"
                      "  (dong (colour x))" "  (deng (display e)))"))
         (list "first bad scale in file order" 2
               (lines "(piece \"P\")" "(scale a 1)" "(scale b (ding (colour x)))")))))

(test-group "degree-ends-in-digit"
  (table-tests 'degree-ends-in-digit
   (list (list "bare name ending in a digit: scale's line" 2
               (lines "(piece \"P\")" "(scale s ding" "  dong2)"))
         (list "listed name ending in a digit: own line" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong2 (alias o)))"))
         (list "alias ending in a digit" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (alias o2)))"))
         (list "second alias ending in a digit" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (alias o o0)))"))
         (list "bare name ending in two digits" 2
               (lines "(piece \"P\")" "(scale s ding a10)")))))

(test-group "duplicate-degree"
  (table-tests 'duplicate-degree
   (list (list "same name twice, bare: scale's line" 2
               (lines "(piece \"P\")" "(scale s ding dong" "  ding)"))
         (list "same name twice, second listed: its line" 3
               (lines "(piece \"P\")" "(scale s ding dong" "  (ding (alias i)))"))
         (list "alias equal to another degree's name" 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (alias ding)))"))
         (list "name equal to an earlier alias" 3
               (lines "(piece \"P\")" "(scale s (ding (alias i))" "  (i (alias x)))"))
         (list "alias equal to an earlier alias" 3
               (lines "(piece \"P\")" "(scale s (ding (alias i))" "  (dong (alias i)))"))
         (list "alias equal to its own degree's name" 2
               (lines "(piece \"P\")" "(scale s (ding (alias ding)) dong)"))
         (list "alias repeated in one alias list" 2
               (lines "(piece \"P\")" "(scale s (ding (alias i i)) dong)"))
         (list "stroke name twice" 2
               (lines "(piece \"P\")" "(strokes k G P G)"))
         (list "stroke alias equal to another stroke" 3
               (lines "(piece \"P\")" "(strokes k G" "  (P (alias G)))"))
         (list "stroke alias equal to its own name" 2
               (lines "(piece \"P\")" "(strokes k (G (alias G)))")))))

(test-group "undefined-scale"
  (table-tests 'undefined-scale
   (list (list "nothing defined" 2
               (lines "(piece \"P\")" "(instrument ugal selisir ding1)"))
         (list "a different scale is defined" 3
               (lines "(piece \"P\")" "(scale pelog ding)"
                      "(instrument ugal selisir ding1)"))
         (list "names are case-sensitive" 3
               (lines "(piece \"P\")" "(scale selisir ding)"
                      "(instrument ugal Selisir ding1)"))
         (list "naming an instrument, not a scale" 4
               (lines "(piece \"P\")" "(strokes g G)" "(instrument gong g G)"
                      "(instrument kempli gong G)"))
         (list "multi-line instrument: the form's line" 2
               (lines "(piece \"P\")" "(instrument ugal" "  selisir ding1)"))
         (list "first instrument in file order" 3
               (lines "(piece \"P\")" "(scale s ding)" "(instrument a x ding1)"
                      "(instrument b y ding1)")))))

(test-group "unknown-note"
  (table-tests 'unknown-note
   (list (list "degree not in the scale" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding1 dang1)"))
         (list "pitched note without an octave" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding)"))
         (list "alias without an octave" 3
               (lines "(piece \"P\")" "(scale s (ding (alias i)) dong)"
                      "(instrument x s i)"))
         (list "stroke not in the stroke set" 3
               (lines "(piece \"P\")" "(strokes g G P)"
                      "(instrument gong g G K)"))
         (list "stroke with an octave-like digit" 3
               (lines "(piece \"P\")" "(strokes g G P)"
                      "(instrument gong g G1)"))
         (list "stroke name without its trailing digit" 3
               (lines "(piece \"P\")" "(strokes k k1 k2)"
                      "(instrument x k k)"))
         (list "a note on a continuation line: the instrument's line" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s" "  ding1" "  dang1)"))
         (list "first instrument in file order" 3
               (lines "(piece \"P\")" "(scale s ding)" "(instrument a s foo1)"
                      "(instrument b s bar1)")))))

(test-group "notes-not-ascending"
  (table-tests 'notes-not-ascending
   (list (list "lower octave after higher" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding2 ding1)"))
         (list "lower degree after higher, same octave" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s dong1 ding1)"))
         (list "repeated note" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding1 ding1)"))
         (list "repeated note through an alias" 3
               (lines "(piece \"P\")" "(scale s (ding (alias i)) dong)"
                      "(instrument x s ding1 i1)"))
         (list "octave 0 after octave 1" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding1 dong0)"))
         (list "octave 9 after octave 10 (numbers, not text)" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding10 dong9)"))
         (list "a later note out of order" 3
               (lines "(piece \"P\")" "(scale s ding dong)"
                      "(instrument x s ding1 dong1 ding2 dong1)")))))

(test-group "duplicate-note"
  (table-tests 'duplicate-note
   (list (list "stroke listed twice" 3
               (lines "(piece \"P\")" "(strokes g G P)"
                      "(instrument gong g G P G)"))
         (list "stroke listed twice through an alias" 3
               (lines "(piece \"P\")" "(strokes k (dag (alias D)) dug)"
                      "(instrument kendang k dag dug D)"))
         (list "stroke ending in a digit listed twice" 3
               (lines "(piece \"P\")" "(strokes k k1 k2)"
                      "(instrument x k k2 k1 k2)")))))

(test-group "slice 2 error fields"
  (for-each
   (match-lambda
     ((name kind str)
      (let ((c (catch-syntax-error (lambda () (read-piece-string str)))))
        (test-equal (string-append name ": kind") kind (kind-of c))
        (test-equal (string-append name ": file #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
        (test-equal (string-append name ": part #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-part c)))
        (test-equal (string-append name ": step #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-step c))))))
   (list (list "bad-form" 'bad-form (lines "(piece \"P\")" "(scale s)"))
         (list "bad-degree" 'bad-degree
               (lines "(piece \"P\")" "(scale s (ding (colour x)))"))
         (list "undefined-scale" 'undefined-scale
               (lines "(piece \"P\")" "(instrument x s ding1)"))
         (list "unknown-note" 'unknown-note
               (lines "(piece \"P\")" "(scale s ding)" "(instrument x s dong1)"))))

  (for-each
   (match-lambda
     ((name kind line contents)
      (let* ((path (write-temp-file (string-append name ".nts") contents))
             (c (catch-syntax-error (lambda () (read-piece-file path)))))
        (test-equal (string-append name " from a file: kind") kind (kind-of c))
        (test-equal (string-append name " from a file: file") path
          (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
        (test-equal (string-append name " from a file: line") line
          (and (notasi-syntax-error? c) (notasi-syntax-error-line c)))
        (test-equal (string-append name " from a file: part #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-part c)))
        (test-equal (string-append name " from a file: step #f") #f
          (and (notasi-syntax-error? c) (notasi-syntax-error-step c))))))
   (list (list "bad-form" 'bad-form 2 (lines "(piece \"P\")" "(strokes g)"))
         (list "duplicate-definition" 'duplicate-definition 3
               (lines "(piece \"P\")" "(scale s ding)" "(strokes s G)"))
         (list "bad-degree" 'bad-degree 3
               (lines "(piece \"P\")" "(scale s ding" "  (dong (alias)))"))
         (list "degree-ends-in-digit" 'degree-ends-in-digit 2
               (lines "(piece \"P\")" "(scale s ding1)"))
         (list "duplicate-degree" 'duplicate-degree 2
               (lines "(piece \"P\")" "(scale s ding ding)"))
         (list "undefined-scale" 'undefined-scale 2
               (lines "(piece \"P\")" "(instrument x s ding1)"))
         (list "unknown-note" 'unknown-note 3
               (lines "(piece \"P\")" "(scale s ding)" "(instrument x s ding)"))
         (list "notes-not-ascending" 'notes-not-ascending 3
               (lines "(piece \"P\")" "(scale s ding)"
                      "(instrument x s ding2 ding1)"))
         (list "duplicate-note" 'duplicate-note 3
               (lines "(piece \"P\")" "(strokes g G)" "(instrument x g G G)")))))

;;; ------------------------------------------------------------------
;;; Check order (03-reader.md, "Error reporting", items 5 to 10)

(test-group "slice 2 check order"
  (for-each
   (match-lambda
     ((name expected str)
      (test-equal name expected (string-error str))))
   (list
    ;; Items 1-4 come before definitions.
    (list "unknown-form comes before bad-form" '(unknown-form 3)
          (lines "(piece \"P\")" "(scale)" "(foo)"))
    (list "bad-title comes before bad-form" '(bad-title 1)
          (lines "(piece 1)" "(scale)"))
    (list "bad-option comes before undefined-scale" '(bad-option 1)
          (lines "(piece \"P\" (steps-per-pulse 0))" "(instrument x s ding1)"))
    ;; Item 5: use.
    (list "a template's scale is defined for the piece's instruments" 'no-error
          (lines "(piece \"P\")" "(use gong-kebyar)"
                 "(instrument ugal selisir ding1)"))
    (list "use, then the piece's own bad-form" '(bad-form 3)
          (lines "(piece \"P\")" "(use gong-kebyar)" "(scale)"))
    (list "template-not-found comes before unknown-note" '(template-not-found 2)
          (lines "(piece \"P\")" "(use \"defs.nts\")" "(scale s ding)"
                 "(instrument x s dong1)"))
    ;; Item 6 before 7.
    (list "bad-form comes before duplicate-definition" '(bad-form 4)
          (lines "(piece \"P\")" "(scale s ding)" "(scale s dong)" "(instrument x)"))
    (list "bad-form comes before an earlier duplicate instrument" '(bad-form 5)
          (lines "(piece \"P\")" "(strokes g G)" "(instrument x g G)"
                 "(instrument x g G)" "(strokes)"))
    ;; Item 7 before 8 and 9.
    (list "duplicate-definition comes before bad-degree" '(duplicate-definition 3)
          (lines "(piece \"P\")" "(scale s (ding (colour x)))" "(scale s dong)"))
    (list "duplicate-definition comes before duplicate-degree"
          '(duplicate-definition 3)
          (lines "(piece \"P\")" "(scale s ding ding)" "(strokes s G)"))
    (list "duplicate-definition comes before undefined-scale"
          '(duplicate-definition 3)
          (lines "(piece \"P\")" "(instrument x nowhere ding1)"
                 "(instrument x nowhere ding1)"))
    ;; Item 8 before 9.
    (list "scale errors before instrument errors, instrument first"
          '(bad-degree 3)
          (lines "(piece \"P\")" "(instrument x nowhere ding1)"
                 "(scale s (ding (colour x)))"))
    (list "degree-ends-in-digit before unknown-note in an earlier instrument"
          '(degree-ends-in-digit 3)
          (lines "(piece \"P\")" "(instrument x s foo1)" "(scale s ding1)"))
    (list "duplicate-degree before undefined-scale in an earlier instrument"
          '(duplicate-degree 3)
          (lines "(piece \"P\")" "(instrument x nowhere ding1)"
                 "(strokes k G G)"))
    ;; Item 8: within a scale, degree by degree.
    (list "within a degree: bad-degree before degree-ends-in-digit"
          '(bad-degree 2)
          (lines "(piece \"P\")" "(scale s (ding1 (colour x)))"))
    (list "within a degree: degree-ends-in-digit before duplicate-degree"
          '(degree-ends-in-digit 2)
          (lines "(piece \"P\")" "(scale s (ding (alias ding i1)))"))
    (list "within a degree: bad-degree before duplicate-degree"
          '(bad-degree 3)
          (lines "(piece \"P\")" "(scale s ding" "  (ding (alias)))"))
    (list "an earlier degree's duplicate before a later bad degree"
          '(duplicate-degree 2)
          (lines "(piece \"P\")" "(scale s ding ding" "  (dong (colour x)))"))
    (list "an earlier degree's digit before a later bad degree"
          '(degree-ends-in-digit 2)
          (lines "(piece \"P\")" "(scale s ding1" "  (dong (colour x)))"))
    (list "an earlier scale's error before a later scale's" '(duplicate-degree 2)
          (lines "(piece \"P\")" "(scale a ding ding)" "(scale b (ding (colour x)))"))
    ;; Item 9: within an instrument, note by note.
    (list "undefined-scale before a later instrument's unknown-note"
          '(undefined-scale 3)
          (lines "(piece \"P\")" "(scale s ding)" "(instrument a nowhere ding1)"
                 "(instrument b s foo1)"))
    (list "an earlier note's ordering error before a later unknown note"
          '(notes-not-ascending 3)
          (lines "(piece \"P\")" "(scale s ding dong)"
                 "(instrument x s dong1 ding1 foo1)"))
    (list "an earlier unknown note before a later ordering error"
          '(unknown-note 3)
          (lines "(piece \"P\")" "(scale s ding dong)"
                 "(instrument x s foo1 dong1 ding1)"))
    (list "an earlier stroke duplicate before a later unknown stroke"
          '(duplicate-note 3)
          (lines "(piece \"P\")" "(strokes g G P)" "(instrument x g G G K)"))
    ;; Item 10: part, group and text come last.
    (list "unknown-note comes before a part's errors" '(unknown-note 4)
          (lines "(piece \"P\")" "(part p x 1)" "(scale s ding)"
                 "(instrument x s foo1)"))
    (list "undefined-scale comes before a group's errors"
          '(undefined-scale 3)
          (lines "(piece \"P\")" "(group \"G\" p)" "(instrument x s ding1)"))
    (list "bad-form comes before text's not-implemented" '(bad-form 3)
          (lines "(piece \"P\")" "(text \"x\")" "(scale s)"))
    (list "duplicate-note comes before a part's errors"
          '(duplicate-note 4)
          (lines "(piece \"P\")" "(strokes g G)" "(part p x 1)"
                 "(instrument x g G G)"))
    (list "valid definitions, then a text: not-implemented at the text"
          '(not-implemented 4)
          (lines "(piece \"P\")" "(strokes g G)" "(instrument x g G)"
                 "(text \"x\")"))
    (list "valid definitions after a text: not-implemented at the text"
          '(not-implemented 2)
          (lines "(piece \"P\")" "(text \"x\")" "(strokes g G)"
                 "(instrument x g G)")))))

(test-group "slice 2: cases decided at review"
  (test-equal "instrument's scale is a string: bad-form" '(bad-form 3)
    (string-error (lines "(piece \"P\")" "(strokes g G)"
                         "(instrument gong \"g\" G)")))
  (test-equal "instrument note is a number: bad-form" '(bad-form 3)
    (string-error (lines "(piece \"P\")" "(strokes g G)"
                         "(instrument gong g 1)")))
  (test-equal "alias is a string: bad-degree" '(bad-degree 2)
    (string-error (lines "(piece \"P\")" "(scale s (ding (alias \"i\")))")))
  (test-equal "leading-zero octave: unknown-note" '(unknown-note 3)
    (string-error (lines "(piece \"P\")" "(scale s ding)"
                         "(instrument x s ding02)")))
  (test-equal "degree option on its own line: the degree's line" '(bad-degree 3)
    (string-error (lines "(piece \"P\")" "(scale s"
                         "  (ding"
                         "    (colour \"red\")))"))))

;;; ==================================================================
;;; Slice 3: part and group forms
;;; ==================================================================

;;; ------------------------------------------------------------------
;;; Helpers for slice 3

;;; Definitions used by most slice 3 tests. Forms added after them start
;;; on line 10.
;;;   reyong (8 notes): 1 deng1  2 dung1  3 dang1  4 ding2
;;;                     5 dong2  6 deng2  7 dung2  8 dang2
;;;   ugal (6 notes):   1 dong1  2 deng1  3 dung1  4 dang1  5 ding2  6 dong2
;;;   gong (2 notes):   1 G  2 P
;;;   kempli (1 note):  1 K
(define parts-defs
  (lines "(piece \"Parts\")"                                       ; 1
         "(scale selisir (ding (alias i)) (dong (alias o))"        ; 2
         "  (deng (alias e)) (dung (alias u)) (dang (alias a)))"   ; 3
         "(strokes gong-strokes G P)"                              ; 4
         "(strokes kempli-strokes K)"                              ; 5
         "(instrument reyong selisir e1 u1 a1 i2 o2 e2 u2 a2)"     ; 6
         "(instrument ugal selisir o1 e1 u1 a1 i2 o2)"             ; 7
         "(instrument gong gong-strokes G P)"                      ; 8
         "(instrument kempli kempli-strokes K)"))                  ; 9

(define (defs+ . more)
  "parts-defs followed by the lines MORE, which start on line 10."
  (apply lines parts-defs more))

(define (read-defs+ . more)
  "Read parts-defs plus MORE as a piece, or #f if reading raises."
  (try-read-string (apply defs+ more)))

(define (part-named pc name) (find-named part-name name (piece-parts pc)))

(define (group-labelled pc label)
  (or (find (lambda (g) (equal? (group-label g) label)) (piece-groups pc))
      (error "no group labelled:" label)))

(define (event-triple e)
  (list (event-start e) (event-duration e) (event-notes e)))

(define (part-triples pc name)
  "The events of part NAME as (START DURATION NOTES) triples."
  (map event-triple (part-events (part-named pc name))))

(define (part-p-events instrument tokens)
  "Read parts-defs plus (part p INSTRUMENT TOKENS), and return p's events
as (START DURATION NOTES) triples."
  (part-triples (read-defs+ (string-append "(part p " instrument " "
                                           tokens ")"))
                'p))

(define (group-part-names g) (map part-name (group-parts g)))

(define (group-line g)
  (and=> (group-location g) source-location-line))

(define (error-fields str)
  "(KIND LINE PART STEP) of the &notasi-syntax-error raised reading STR,
or the raised object (or no-error) unchanged."
  (let ((c (catch-syntax-error (lambda () (read-piece-string str)))))
    (if (notasi-syntax-error? c)
        (list (notasi-syntax-error-kind c) (notasi-syntax-error-line c)
              (notasi-syntax-error-part c) (notasi-syntax-error-step c))
        c)))

(define (error-kind+line+part str)
  "(KIND LINE PART) of the &notasi-syntax-error raised reading STR."
  (let ((c (catch-syntax-error (lambda () (read-piece-string str)))))
    (if (notasi-syntax-error? c)
        (list (notasi-syntax-error-kind c) (notasi-syntax-error-line c)
              (notasi-syntax-error-part c))
        c)))

(define (token-tests expected-kind cases)
  "CASES is a list of (NAME INSTRUMENT TOKENS STEP). Each reads
parts-defs plus (part p INSTRUMENT TOKENS) on line 10, and expects
EXPECTED-KIND at line 10, part p, step STEP."
  (for-each
   (match-lambda
     ((name instrument tokens step)
      (test-equal name (list expected-kind 10 'p step)
        (error-fields
         (defs+ (string-append "(part p " instrument " " tokens ")"))))))
   cases))

;;; ------------------------------------------------------------------
;;; Successful reads: events

(test-group "part events"
  (for-each
   (match-lambda
     ((name instrument tokens expected)
      (test-equal name expected (part-p-events instrument tokens))))
   (list
    (list "single notes by number, 0-based" "reyong" "1 2 8"
          '((0 1 (0)) (1 1 (1)) (2 1 (7))))
    (list "single notes by name" "reyong" "deng1 ding2 dang2"
          '((0 1 (0)) (1 1 (3)) (2 1 (7))))
    (list "single notes by alias: resolved" "reyong" "e1 i2 a2"
          '((0 1 (0)) (1 1 (3)) (2 1 (7))))
    (list "number, alias and name of one note" "reyong" "4 i2 ding2"
          '((0 1 (3)) (1 1 (3)) (2 1 (3))))
    (list "notes on ugal" "ugal" "6 o1 5"
          '((0 1 (5)) (1 1 (0)) (2 1 (4))))
    (list "_ holds extend the duration" "reyong" "1 _ _ 2 _ 3"
          '((0 3 (0)) (3 2 (1)) (5 1 (2))))
    (list "- rests leave gaps" "reyong" "1 - 2 - - 3"
          '((0 1 (0)) (2 1 (1)) (5 1 (2))))
    (list "· rests leave gaps" "reyong" "1 · 2 · · 3"
          '((0 1 (0)) (2 1 (1)) (5 1 (2))))
    (list "- and · mixed" "reyong" "1 - · 2"
          '((0 1 (0)) (3 1 (1))))
    (list "a rest first" "reyong" "- 1"
          '((1 1 (0))))
    (list "a rest ends a held note" "reyong" "1 _ - 2"
          '((0 2 (0)) (3 1 (1))))
    (list "only rests: no events" "gong" "- - · -"
          '())
    (list "/ takes no step" "reyong" "1 / 2 / / 3"
          '((0 1 (0)) (1 1 (1)) (2 1 (2))))
    (list "_ after / extends the note before it" "reyong" "1 _ / _ 2 / _ 3"
          '((0 3 (0)) (3 2 (1)) (5 1 (2))))
    (list "/ at the start and the end" "reyong" "/ 1 2 /"
          '((0 1 (0)) (1 1 (1))))
    (list "chord by number, sorted ascending" "reyong" "(5 2)"
          '((0 1 (1 4))))
    (list "chord by name, sorted ascending" "reyong" "(i2 deng1)"
          '((0 1 (0 3))))
    (list "chord mixing number and name" "reyong" "(8 deng2)"
          '((0 1 (5 7))))
    (list "three-note chord" "reyong" "(3 1 2)"
          '((0 1 (0 1 2))))
    (list "chords and single notes" "reyong" "(1 3) 2 (u2 o2)"
          '((0 1 (0 2)) (1 1 (1)) (2 1 (4 6))))
    (list "chord on ugal" "ugal" "(a1 5)"
          '((0 1 (3 4))))
    (list "chord followed by _" "reyong" "(1 3) _ _ 2"
          '((0 3 (0 2)) (3 1 (1))))
    (list "chord, /, then _" "reyong" "(1 3) / _ 2"
          '((0 2 (0 2)) (2 1 (1))))
    (list "last note held to the end" "reyong" "1 2 _ _"
          '((0 1 (0)) (1 3 (1))))
    (list "trailing rests are not stored" "reyong" "1 2 - -"
          '((0 1 (0)) (1 1 (1))))
    (list "strokes by name" "gong" "G - P _"
          '((0 1 (0)) (2 2 (1))))
    (list "strokes by number" "gong" "2 1"
          '((0 1 (1)) (1 1 (0))))
    (list "chord of strokes" "gong" "(P G)"
          '((0 1 (0 1))))))

  (test-assert "events are event records"
    (every event? (part-events (part-named (read-defs+ "(part p reyong 1 _ 2)")
                                           'p)))))

(test-group "piece length"
  (for-each
   (match-lambda
     ((name expected . forms)
      (test-equal name expected (piece-length (apply read-defs+ forms)))))
   (list (list "one step per token" 3 "(part p reyong 1 2 3)")
         (list "holds count" 4 "(part p reyong 1 _ _ 2)")
         (list "trailing rests count" 4 "(part p reyong 1 2 - -)")
         (list "a part of only rests" 3 "(part p gong - · -)")
         (list "/ does not count" 2 "(part p reyong / 1 / 2 /)")
         (list "a chord is one step" 2 "(part p reyong (1 2) (3 4))")
         (list "several parts of equal length" 4
               "(part a reyong 1 2 - -)" "(part b gong G _ _ _)")))
  (let ((pc (read-defs+)))
    (test-equal "no parts: length 0" 0 (piece-length pc))
    (test-equal "no parts: no groups" '() (piece-groups pc)))
  (let ((pc (read-defs+ "(part a reyong 1 2 - -)" "(part b gong G _ _ _)")))
    (test-equal "part-steps is the end of the last event (ADR 0012)" '(2 4)
      (map part-steps (piece-parts pc)))
    (test-assert "part-steps <= piece-length"
      (every (lambda (p) (<= (part-steps p) (piece-length pc)))
             (piece-parts pc)))))

;;; ------------------------------------------------------------------
;;; Successful reads: part fields

(test-group "part fields"
  (let ((pc (read-defs+ "(part polos reyong 1 2 3 4)"    ; 10
                        "(part ugal ugal"                ; 11
                        "  1 2 3 4)"                     ; 12
                        "(part gong gong G - - -)"       ; 13
                        "(part sangsih reyong 4 3 2 1)"))) ; 14
    (test-assert "reads into a piece" (piece? pc))
    (test-equal "parts in file order" '(polos ugal gong sangsih)
      (map part-name (piece-parts pc)))
    (test-assert "parts are part records" (every part? (piece-parts pc)))
    (test-equal "part instruments by name" '(reyong ugal gong reyong)
      (map (lambda (p) (instrument-name (part-instrument p)))
           (piece-parts pc)))
    (test-assert "part instrument is the instrument record in the piece"
      (and (eq? (part-instrument (part-named pc 'polos))
                (instrument-named pc 'reyong))
           (eq? (part-instrument (part-named pc 'sangsih))
                (instrument-named pc 'reyong))
           (eq? (part-instrument (part-named pc 'ugal))
                (instrument-named pc 'ugal))
           (eq? (part-instrument (part-named pc 'gong))
                (instrument-named pc 'gong))))
    (test-equal "part lines: the form's line" '(10 11 13 14)
      (map (lambda (p) (source-location-line (part-location p)))
           (piece-parts pc)))
    (test-equal "part files are #f from a string" '(#f #f #f #f)
      (map (lambda (p) (source-location-file (part-location p)))
           (piece-parts pc)))
    (test-equal "length" 4 (piece-length pc))
    (test-equal "instruments still in file order" '(reyong ugal gong kempli)
      (map instrument-name (piece-instruments pc))))

  (let ((pc (read-defs+ "(part ugal ugal 1 2)")))
    (test-equal "(part ugal ugal ...): the part's name" '(ugal)
      (map part-name (piece-parts pc)))
    (test-assert "(part ugal ugal ...): its instrument"
      (eq? (part-instrument (part-named pc 'ugal)) (instrument-named pc 'ugal)))
    (test-equal "(part ugal ugal ...): its default group" '("ugal")
      (map group-label (piece-groups pc))))

  (let ((pc (read-defs+ "(part selisir reyong 1)"
                        "(part gong-strokes gong G)"
                        "(part reyong ugal 1)")))
    (test-equal "parts may share names with scales, stroke sets, instruments"
      '(selisir gong-strokes reyong)
      (map part-name (piece-parts pc)))
    (test-assert "a part named like another instrument plays its own"
      (eq? (part-instrument (part-named pc 'reyong))
           (instrument-named pc 'ugal)))))

(test-group "parts and groups read from a file"
  (let* ((path (write-temp-file "parts.nts"
                                (defs+ "(part a reyong 1 2)"     ; 10
                                       "(part b reyong 3 4)"     ; 11
                                       "(group \"AB\" a b)")))   ; 12
         (pc (try-read (lambda () (read-piece-file path)))))
    (test-equal "part files are the path given" (list path path)
      (map (lambda (p) (source-location-file (part-location p)))
           (piece-parts pc)))
    (test-equal "part lines" '(10 11)
      (map (lambda (p) (source-location-line (part-location p)))
           (piece-parts pc)))
    (test-equal "group file is the path given" path
      (source-location-file (group-location (group-labelled pc "AB"))))
    (test-equal "group line" 12 (group-line (group-labelled pc "AB")))))

;;; ------------------------------------------------------------------
;;; Successful reads: groups

(test-group "groups"
  (let ((pc (read-defs+ "(part ugal    ugal   1 2 3 4)"      ; 10
                        "(part polos   reyong 1 2 3 4)"      ; 11
                        "(part sangsih reyong 4 3 2 1)"      ; 12
                        "(part gong    gong   G - - P)"      ; 13
                        "(group \"Reyong\" polos sangsih)"))) ; 14
    (test-equal "the doc's example: ugal, Reyong, gong" '("ugal" "Reyong" "gong")
      (map group-label (piece-groups pc)))
    (test-assert "groups are group records" (every group? (piece-groups pc)))
    (test-equal "group parts" '((ugal) (polos sangsih) (gong))
      (map group-part-names (piece-groups pc)))
    (test-equal "subtitles: #f by default" '(#f #f #f)
      (map group-subtitle (piece-groups pc)))
    (test-equal "locations: #f for default groups, the form's line otherwise"
      '(#f 14 #f)
      (map group-line (piece-groups pc)))
    (test-equal "a written group's file is #f from a string" #f
      (source-location-file (group-location (group-labelled pc "Reyong"))))
    (test-assert "a written group's parts are the piece's part records"
      (equal? (map (lambda (p) (eq? p (part-named pc (part-name p))))
                   (group-parts (group-labelled pc "Reyong")))
              '(#t #t)))
    (test-assert "a default group's part is the piece's part record"
      (eq? (car (group-parts (group-labelled pc "ugal")))
           (part-named pc 'ugal)))
    (test-equal "every part is in exactly one group"
      '(gong polos sangsih ugal)
      (sort (append-map group-part-names (piece-groups pc))
            (lambda (a b) (string<? (symbol->string a) (symbol->string b)))))
    (test-equal "parts stay in file order" '(ugal polos sangsih gong)
      (map part-name (piece-parts pc))))

  (let ((pc (read-defs+ "(group \"Reyong\" sangsih polos"      ; 10
                        "  (subtitle \"polos + sangsih\"))"    ; 11
                        "(part ugal    ugal   1 2 3 4)"        ; 12
                        "(part polos   reyong 1 2 3 4)"        ; 13
                        "(part sangsih reyong 4 3 2 1)"        ; 14
                        "(part gong    gong   G - - P)")))     ; 15
    (test-equal "group before its parts: order by parts" '("ugal" "Reyong" "gong")
      (map group-label (piece-groups pc)))
    (test-equal "a group's parts in the order the group lists them"
      '(sangsih polos)
      (group-part-names (group-labelled pc "Reyong")))
    (test-equal "given subtitle" "polos + sangsih"
      (group-subtitle (group-labelled pc "Reyong")))
    (test-equal "group line: the form's line" 10
      (group-line (group-labelled pc "Reyong")))
    (test-equal "default groups still have no subtitle" '(#f #f)
      (map group-subtitle (list (group-labelled pc "ugal")
                                (group-labelled pc "gong")))))

  (let ((pc (read-defs+ "(part a reyong 1)"
                        "(part b reyong 2)"
                        "(part c reyong 3)"
                        "(group \"CA\" c a)")))
    (test-equal "a group goes where its earliest part in the file is"
      '("CA" "b")
      (map group-label (piece-groups pc)))
    (test-equal "its parts stay in the group's order" '(c a)
      (group-part-names (group-labelled pc "CA"))))

  (let ((pc (read-defs+ "(part a reyong 1)"
                        "(part b reyong 2)"
                        "(part c reyong 3)"
                        "(part d reyong 4)"
                        "(group \"CD\" c d)"
                        "(group \"AB\" a b)")))
    (test-equal "written groups ordered by their parts, not by the group forms"
      '("AB" "CD")
      (map group-label (piece-groups pc))))

  (let ((pc (read-defs+ "(part a reyong 1)"
                        "(part b reyong 2)"
                        "(part c gong G)"
                        "(part d reyong 4)"
                        "(part e kempli K)"
                        "(group \"BD\" b d)")))
    (test-equal "written and default groups interleaved" '("a" "BD" "c" "e")
      (map group-label (piece-groups pc))))

  (let ((pc (read-defs+ "(part a reyong 1)"
                        "(part b reyong 2)"
                        "(group \"All\" a b)")))
    (test-equal "all parts in one group: no default groups" '("All")
      (map group-label (piece-groups pc))))

  (let ((pc (read-defs+ "(part a reyong 1)"
                        "(part b reyong 2)")))
    (test-equal "no group forms: one default group per part" '("a" "b")
      (map group-label (piece-groups pc)))
    (test-equal "default groups: one part each" '((a) (b))
      (map group-part-names (piece-groups pc)))
    (test-equal "default groups: subtitle and location #f" '((#f #f) (#f #f))
      (map (lambda (g) (list (group-subtitle g) (group-location g)))
           (piece-groups pc)))))

(test-group "groups that are allowed"
  (let ((pc (read-defs+ "(part kempli kempli K K)"
                        "(part gong gong P G)"
                        "(group \"Time\" gong kempli)")))
    (test-equal "two stroke instruments in one group" '(gong kempli)
      (group-part-names (group-labelled pc "Time")))
    (test-equal "group-lanes: one block per instrument, in group order"
      '(G P K)
      (map note-name (group-lanes (group-labelled pc "Time")))))

  (let ((pc (read-defs+ "(part ugal ugal 1 2)"
                        "(part kempli kempli K K)"
                        "(group \"Ugal and kempli\" ugal kempli)")))
    (test-equal "a pitched instrument with a stroke instrument" '(ugal kempli)
      (group-part-names (group-labelled pc "Ugal and kempli"))))

  (let ((pc (read-defs+ "(part polos reyong 1 2)"
                        "(part sangsih reyong 3 4)"
                        "(group \"Reyong\" polos sangsih)")))
    (test-equal "several parts on the same pitched instrument" '(polos sangsih)
      (group-part-names (group-labelled pc "Reyong")))
    (test-equal "group-lanes: highest first" '(ding2 dang1 dung1 deng1)
      (map note-name (group-lanes (group-labelled pc "Reyong")))))

  (let ((pc (read-defs+ "(part polos reyong 1 2)"
                        "(part kempli kempli K K)"
                        "(part sangsih reyong 3 4)"
                        "(part gong gong G P)"
                        "(group \"All\" polos kempli sangsih gong)")))
    (test-equal "one pitched instrument and two stroke instruments"
      '(polos kempli sangsih gong)
      (group-part-names (group-labelled pc "All")))))

;;; ------------------------------------------------------------------
;;; The textbook excerpt at the end of 01-notation.md

(test-group "textbook excerpt"
  (let ((pc (try-read-string
             "(piece \"Reyong kotekan\" (steps-per-pulse 4))"
             "(scale reyong-4  nang ning nong neng)          ; do mi fa sol"
             "(strokes gong-strokes  G)"
             "(instrument reyong reyong-4  nang1 ning1 nong1 neng1)"
             "(instrument gong gong-strokes G)"
             ""
             "(part polos   reyong  1 _ 1 2 / _ 1 2 _ / 2 1 _ 2)"
             "(part sangsih reyong  4 3 4 _ / 3 4 _ 3 / _ 4 3 _)"
             "(part gong    gong    1 - - - / - - - - / - - - -)"
             "(group \"Reyong\" polos sangsih)")))
    (test-assert "reads into a piece" (piece? pc))
    (test-equal "title" "Reyong kotekan" (piece-title pc))
    (test-equal "steps-per-pulse" 4 (piece-steps-per-pulse pc))
    (test-equal "length: 12 steps" 12 (piece-length pc))
    (test-equal "parts" '(polos sangsih gong) (map part-name (piece-parts pc)))
    (test-equal "part lines" '(7 8 9)
      (map (lambda (p) (source-location-line (part-location p)))
           (piece-parts pc)))
    (test-equal "polos events"
      '((0 2 (0)) (2 1 (0)) (3 2 (1)) (5 1 (0))
        (6 2 (1)) (8 1 (1)) (9 2 (0)) (11 1 (1)))
      (part-triples pc 'polos))
    (test-equal "sangsih events"
      '((0 1 (3)) (1 1 (2)) (2 2 (3)) (4 1 (2))
        (5 2 (3)) (7 2 (2)) (9 1 (3)) (10 2 (2)))
      (part-triples pc 'sangsih))
    (test-equal "gong events" '((0 1 (0))) (part-triples pc 'gong))
    (test-equal "groups" '("Reyong" "gong") (map group-label (piece-groups pc)))
    (test-equal "group parts" '((polos sangsih) (gong))
      (map group-part-names (piece-groups pc)))
    (test-equal "group lines" '(10 #f) (map group-line (piece-groups pc)))
    ;; Light checks with the derived functions of (notasi piece).
    (test-equal "group-lanes: Reyong, highest first" '(neng1 nong1 ning1 nang1)
      (map note-name (group-lanes (group-labelled pc "Reyong"))))
    (test-equal "group-lanes: gong" '(G)
      (map note-name (group-lanes (group-labelled pc "gong"))))
    (test-equal "part-steps" '(12 12 1) (map part-steps (piece-parts pc)))
    (test-assert "part-steps <= piece-length"
      (every (lambda (p) (<= (part-steps p) (piece-length pc)))
             (piece-parts pc)))
    (test-equal "events-at step 8: polos starts, sangsih holds"
      '((polos 8 (1)) (sangsih 7 (2)))
      (map (match-lambda
             ((p . e) (list (part-name p) (event-start e) (event-notes e))))
           (events-at pc 8)))
    (test-equal "events-at step 0: all three parts"
      '((polos 0 (0)) (sangsih 0 (3)) (gong 0 (0)))
      (map (match-lambda
             ((p . e) (list (part-name p) (event-start e) (event-notes e))))
           (events-at pc 0)))))

;;; ------------------------------------------------------------------
;;; Token errors. Each is at the part's line (10), part p, and the
;;; token's 0-based step.

(test-group "note-out-of-range"
  (token-tests 'note-out-of-range
   (list (list "0" "reyong" "1 0 2" 1)
         (list "n+1" "reyong" "1 2 9" 2)
         (list "a negative number" "reyong" "-1 1" 0)
         (list "n+1 on ugal (6 notes)" "ugal" "7" 0)
         (list "n+1 on a stroke instrument" "gong" "G 3" 1)
         (list "out of range in a chord" "reyong" "1 (1 9)" 1)
         (list "0 in a chord" "reyong" "(0 1)" 0))))

(test-group "unknown-note in a part"
  (token-tests 'unknown-note
   (list (list "name not in the scale" "reyong" "1 foo1" 1)
         (list "pitched name without an octave" "reyong" "ding" 0)
         (list "alias without an octave" "reyong" "1 2 i" 2)
         (list "in the scale but not on the instrument" "reyong" "ding1" 0)
         (list "alias of a note not on the instrument" "reyong" "i1" 0)
         (list "above the instrument's range" "reyong" "1 ding3" 1)
         (list "leading-zero octave" "reyong" "i02" 0)
         (list "names are case-sensitive" "reyong" "Ding2" 0)
         (list "a stroke on a pitched instrument" "reyong" "G" 0)
         (list "a pitched note on a stroke instrument" "gong" "ding2" 0)
         (list "a stroke from another stroke set" "gong" "G K" 1)
         (list "a stroke with an octave-like digit" "gong" "G1" 0)
         (list "unknown name in a chord" "reyong" "(1 foo1)" 0)
         (list "chord member not on the instrument" "reyong" "1 (ding1 2)" 1))))

(test-group "hold-without-note"
  (token-tests 'hold-without-note
   (list (list "_ first" "reyong" "_ 1" 0)
         (list "_ after -" "reyong" "1 - _" 2)
         (list "_ after ·" "reyong" "1 · _" 2)
         (list "_ after a rest first" "gong" "- _" 1)
         (list "_ after a / that follows a rest" "reyong" "1 - / _" 2)
         (list "_ after a / at the start" "reyong" "/ _ 1" 0)
         (list "_ after held note, rest" "reyong" "1 _ - _" 3))))

(test-group "bad-chord"
  (token-tests 'bad-chord
   (list (list "empty chord ()" "reyong" "1 ()" 1)
         (list "chord of one number" "reyong" "(1)" 0)
         (list "chord of one name" "reyong" "1 2 (i2)" 2)
         (list "the same number twice" "reyong" "(2 2)" 0)
         (list "the same name twice" "reyong" "(ding2 ding2)" 0)
         (list "a name and its alias" "reyong" "(ding2 i2)" 0)
         (list "a number, then the same note by name" "reyong" "(1 deng1)" 0)
         (list "a name, then the same note by number" "reyong" "(i2 4)" 0)
         (list "a repeat among three" "reyong" "(1 2 1)" 0)
         (list "the same stroke twice" "gong" "(G G)" 0)
         (list "member _" "reyong" "(1 _)" 0)
         (list "member _ first" "reyong" "1 (_ 2)" 1)
         (list "member -" "reyong" "(1 -)" 0)
         (list "member ·" "reyong" "(1 ·)" 0)
         (list "member /" "reyong" "(1 /)" 0)
         (list "member a string" "reyong" "(1 \"x\")" 0))))

;;; 03-reader.md lists "a list" among bad chord members (bad-chord), but
;;; also lists "a list inside a list" under unknown-token. These tests
;;; follow the bad-chord rule; see the report for the open question.
(test-group "bad-chord: a list as a chord member"
  (token-tests 'bad-chord
   (list (list "member a list" "reyong" "(1 (2 3))" 0)
         (list "member an empty list" "reyong" "1 (2 ())" 1))))

(test-group "unknown-token"
  (token-tests 'unknown-token
   (list (list "a string" "reyong" "1 \"x\"" 1)
         (list "#t" "reyong" "#t" 0)
         (list "1.5" "reyong" "1 2 1.5" 2)
         (list "a vector" "reyong" "1 #(1 2)" 1))))

(test-group "step counting"
  (token-tests 'note-out-of-range
   (list (list "/ takes no step" "reyong" "1 2 / 3 / 9" 3)
         (list "/ before the first token" "reyong" "/ / 9" 0)
         (list "holds and rests take steps" "reyong" "1 _ - · / 2 9" 5)
         (list "a chord takes one step" "reyong" "(1 2) / (3 4) / 9" 2)))
  (token-tests 'hold-without-note
   (list (list "/ around a rest" "reyong" "1 / - / _" 2)))
  (test-equal "a part over several lines: the form's line"
    '(unknown-token 10 p 4)
    (error-fields (defs+ "(part p reyong"
                         "  1 2 3 4 /"
                         "  \"x\")")))
  (test-equal "a later part: its own line and name"
    '(note-out-of-range 11 q 1)
    (error-fields (defs+ "(part p reyong 1 2)" "(part q reyong 1 9)"))))

;;; ------------------------------------------------------------------
;;; Other slice 3 errors

(test-group "unequal-length"
  (for-each
   (match-lambda
     ((name expected . forms)
      (test-equal name expected (error-fields (apply defs+ forms)))))
   (list (list "second part shorter" '(unequal-length 11 b #f)
               "(part a reyong 1 2 3 4)" "(part b reyong 1 2 3)")
         (list "second part longer" '(unequal-length 11 b #f)
               "(part a reyong 1 2 3 4)" "(part b reyong 1 2 3 4 5)")
         (list "third part differs" '(unequal-length 12 c #f)
               "(part a reyong 1 2 3 4)" "(part b gong G - - -)"
               "(part c reyong 1 2 3 4 5)")
         (list "second and third differ: the second" '(unequal-length 11 b #f)
               "(part a reyong 1 2 3 4)" "(part b reyong 1 2 3 4 5)"
               "(part c reyong 1 2 3 4 5)")
         (list "compared with the first part, not the one before"
               '(unequal-length 11 b #f)
               "(part a reyong 1 2 3 4)" "(part b reyong 1 2 3)"
               "(part c reyong 1 2 3 4 5)")
         (list "only trailing rests differ (ADR 0012)" '(unequal-length 11 b #f)
               "(part a reyong 1 2 - -)" "(part b reyong 1 2 -)")
         (list "trailing rests make a part longer" '(unequal-length 11 b #f)
               "(part a gong G)" "(part b gong G - - -)")
         (list "/ does not count towards length" '(unequal-length 11 b #f)
               "(part a reyong 1 / 2 / 3)" "(part b reyong 1 / 2 3 / 4)")
         (list "multi-line part: the form's line" '(unequal-length 11 b #f)
               "(part a reyong 1 2 3 4)" "(part b reyong" "  1 2 3)")))
  (let ((pc (read-defs+ "(part a reyong 1 / 2)" "(part b reyong / 1 2 /)")))
    (test-equal "/ ignored: parts of equal length read" 2 (piece-length pc))))

(test-group "undefined-instrument"
  (for-each
   (match-lambda
     ((name expected . forms)
      (test-equal name expected (error-kind+line+part (apply defs+ forms)))))
   (list (list "nothing by that name" '(undefined-instrument 10 p)
               "(part p nowhere 1)")
         (list "names are case-sensitive" '(undefined-instrument 10 p)
               "(part p Reyong 1)")
         (list "a scale's name" '(undefined-instrument 10 p)
               "(part p selisir 1)")
         (list "a stroke set's name" '(undefined-instrument 10 p)
               "(part p gong-strokes G)")
         (list "another part's name" '(undefined-instrument 11 b)
               "(part a reyong 1)" "(part b a 1)")
         (list "multi-line part: the form's line" '(undefined-instrument 10 p)
               "(part p" "  nowhere 1)"))))

(test-group "undefined-part"
  (for-each
   (match-lambda
     ((name expected . forms)
      (test-equal name expected (error-kind+line+part (apply defs+ forms)))))
   (list (list "undefined part after a defined one" '(undefined-part 11 nope)
               "(part a reyong 1)" "(group \"G\" a nope)")
         (list "only an undefined part" '(undefined-part 11 nope)
               "(part a reyong 1)" "(group \"G\" nope)")
         (list "names are case-sensitive" '(undefined-part 11 A)
               "(part a reyong 1)" "(group \"G\" A)")
         (list "an instrument's name, not a part's" '(undefined-part 11 reyong)
               "(part a reyong 1)" "(group \"G\" reyong)")
         (list "no parts at all" '(undefined-part 10 a)
               "(group \"G\" a)")
         (list "multi-line group: the form's line" '(undefined-part 11 nope)
               "(part a reyong 1)" "(group \"G\"" "  a nope)"))))

(test-group "duplicate-definition of a part"
  (table-tests 'duplicate-definition
   (list (list "part / part" 11
               (defs+ "(part a reyong 1)" "(part a reyong 2)"))
         (list "identical parts are still duplicates" 11
               (defs+ "(part a reyong 1)" "(part a reyong 1)"))
         (list "on different instruments" 12
               (defs+ "(part a reyong 1)" "" "(part a gong G)"))
         (list "three definitions: the second is reported" 11
               (defs+ "(part a reyong 1)" "(part a reyong 2)" "(part a reyong 3)")))))

(test-group "part-in-two-groups"
  (for-each
   (match-lambda
     ((name expected . forms)
      (test-equal name expected (error-kind+line+part (apply defs+ forms)))))
   (list (list "second group repeats a part" '(part-in-two-groups 13 b)
               "(part a reyong 1)" "(part b reyong 2)"
               "(group \"G1\" a b)" "(group \"G2\" b)")
         (list "the first repeated part in the group's order"
               '(part-in-two-groups 14 b)
               "(part a reyong 1)" "(part b reyong 2)"
               "(group \"G1\" a)" "(group \"G2\" b)" "(group \"G3\" b a)")
         (list "groups before their parts" '(part-in-two-groups 11 a)
               "(group \"G1\" a)" "(group \"G2\" a)" "(part a reyong 1)"))))

(test-group "mixed-pitched-group"
  (for-each
   (match-lambda
     ((name expected group)
      (test-equal name expected
        (error-kind+line+part
         (defs+ "(part a reyong 1)"    ; 10
                "(part u ugal 1)"      ; 11
                "(part k kempli K)"    ; 12
                "(part b reyong 2)"    ; 13
                "(part g gong G)"      ; 14
                group)))))             ; 15
   (list (list "reyong then ugal" '(mixed-pitched-group 15 u)
               "(group \"G\" a u)")
         (list "ugal then reyong" '(mixed-pitched-group 15 a)
               "(group \"G\" u a b)")
         (list "a stroke part first" '(mixed-pitched-group 15 a)
               "(group \"G\" k u a)")
         (list "two parts on the first instrument, then another"
               '(mixed-pitched-group 15 u)
               "(group \"G\" a b k u)")
         (list "strokes between the two pitched instruments"
               '(mixed-pitched-group 15 u)
               "(group \"G\" a k g u)"))))

(test-group "bad-form for part and group"
  (table-tests 'bad-form
   (list (list "part with no name" 10 (defs+ "(part)"))
         (list "part name is a string" 10 (defs+ "(part \"p\" reyong 1)"))
         (list "part name is a number" 10 (defs+ "(part 1 reyong 1)"))
         (list "part name is a list" 10 (defs+ "(part (p) reyong 1)"))
         (list "part with a name only" 10 (defs+ "(part p)"))
         (list "part instrument is a string" 10 (defs+ "(part p \"reyong\" 1)"))
         (list "part instrument is a number" 10 (defs+ "(part p 5 1)"))
         (list "part instrument is a list" 10 (defs+ "(part p (reyong) 1)"))
         (list "part with no tokens" 10 (defs+ "(part p reyong)"))
         (list "multi-line part: the form's line" 10
               (defs+ "(part p" "  reyong)"))
         (list "group with no label" 11 (defs+ "(part a reyong 1)" "(group)"))
         (list "group label is a symbol" 11
               (defs+ "(part a reyong 1)" "(group Reyong a)"))
         (list "group label is a number" 11
               (defs+ "(part a reyong 1)" "(group 1 a)"))
         (list "group label is a list" 11
               (defs+ "(part a reyong 1)" "(group (\"G\") a)"))
         (list "group with no part names" 11
               (defs+ "(part a reyong 1)" "(group \"G\")"))
         (list "group with only an option" 11
               (defs+ "(part a reyong 1)" "(group \"G\" (subtitle \"x\"))"))
         (list "group part name is a string" 11
               (defs+ "(part a reyong 1)" "(group \"G\" \"a\")"))
         (list "group part name is a number" 11
               (defs+ "(part a reyong 1)" "(group \"G\" 1)"))
         (list "a later part name is a string" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a \"b\")"))
         (list "a part name after an option" 12
               (defs+ "(part a reyong 1)" "(part b reyong 2)"
                      "(group \"G\" a (subtitle \"x\") b)"))
         (list "multi-line group: the form's line" 11
               (defs+ "(part a reyong 1)" "(group \"G\"" "  (subtitle \"x\")"
                      "  a)")))))

(test-group "group options"
  (table-tests 'bad-option
   (list (list "subtitle with no value" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (subtitle))"))
         (list "subtitle is a symbol" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (subtitle x))"))
         (list "subtitle is a number" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (subtitle 5))"))
         (list "subtitle with two strings" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (subtitle \"x\" \"y\"))"))
         (list "subtitle as a dotted pair" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (subtitle . \"x\"))"))
         (list "option name is a string" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (\"subtitle\" \"x\"))"))
         (list "unknown option of the wrong shape: shape first" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (colour))"))
         (list "option on its own line: the option's line" 12
               (defs+ "(part a reyong 1)" "(group \"G\" a" "  (subtitle 5))"))))
  (table-tests 'unknown-option
   (list (list "unknown option" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (colour \"red\"))"))
         (list "option names are case-sensitive" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (Subtitle \"x\"))"))
         (list "a piece option is not a group option" 11
               (defs+ "(part a reyong 1)" "(group \"G\" a (steps-per-pulse 4))"))
         (list "unknown option after a good one" 11
               (defs+ "(part a reyong 1)"
                      "(group \"G\" a (subtitle \"x\") (colour \"red\"))"))
         (list "option on its own line: the option's line" 13
               (defs+ "(part a reyong 1)" "(group \"G\""
                      "  a" "  (colour \"red\"))"))))
  (table-tests 'duplicate-option
   (list (list "subtitle twice" 11
               (defs+ "(part a reyong 1)"
                      "(group \"G\" a (subtitle \"x\") (subtitle \"y\"))"))
         (list "subtitle twice with the same value" 11
               (defs+ "(part a reyong 1)"
                      "(group \"G\" a (subtitle \"x\") (subtitle \"x\"))"))
         (list "options on their own line: that line" 12
               (defs+ "(part a reyong 1)" "(group \"G\" a"
                      "  (subtitle \"x\") (subtitle \"y\"))")))))

(test-group "slice 3 error fields"
  (let ((c (catch-syntax-error
            (lambda () (read-piece-string (defs+ "(part p reyong 1 9)"))))))
    (test-equal "token error: file #f from a string" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c))))
  (for-each
   (match-lambda
     ((name expected contents)
      (let* ((path (write-temp-file (string-append name ".nts") contents))
             (c (catch-syntax-error (lambda () (read-piece-file path)))))
        (test-equal (string-append name " from a file: kind, line, part, step")
          expected
          (and (notasi-syntax-error? c)
               (list (notasi-syntax-error-kind c) (notasi-syntax-error-line c)
                     (notasi-syntax-error-part c) (notasi-syntax-error-step c))))
        (test-equal (string-append name " from a file: file") path
          (and (notasi-syntax-error? c) (notasi-syntax-error-file c))))))
   (list (list "note-out-of-range" '(note-out-of-range 10 p 1)
               (defs+ "(part p reyong 1 9)"))
         (list "hold-without-note" '(hold-without-note 10 p 0)
               (defs+ "(part p reyong _)"))
         (list "unequal-length" '(unequal-length 11 q #f)
               (defs+ "(part p reyong 1)" "(part q reyong 1 2)")))))

;;; ------------------------------------------------------------------
;;; Instrument options (ADR 0019): (show-names yes) or (show-names no)

(test-group "instrument options"
  (define (show-names? . extra)
    (let ((pc (apply try-read-string
                     "(piece \"P\")"
                     "(strokes gong-strokes G P)"
                     extra)))
      (and pc (instrument-show-names? (instrument-named pc 'gong)))))
  (test-equal "names are hidden by default" #f
    (show-names? "(instrument gong gong-strokes G P)"))
  (test-equal "(show-names yes)" #t
    (show-names? "(instrument gong gong-strokes G P (show-names yes))"))
  (test-equal "(show-names no)" #f
    (show-names? "(instrument gong gong-strokes G P (show-names no))"))
  (test-equal "the option may be on its own line" #t
    (show-names? "(instrument gong gong-strokes G P" "  (show-names yes))"))
  (for-each
   (match-lambda
     ((name expected . strs)
      (test-equal name expected
        (string-error (apply lines "(piece \"P\")" "(strokes gong-strokes G P)"
                             strs)))))
   (list
    (list "a value other than yes or no" '(bad-option 3)
          "(instrument gong gong-strokes G (show-names #t))")
    (list "an option with no value" '(bad-option 3)
          "(instrument gong gong-strokes G (show-names))")
    (list "an unknown option" '(unknown-option 3)
          "(instrument gong gong-strokes G (colour red))")
    (list "an option given twice" '(duplicate-option 4)
          "(instrument gong gong-strokes G (show-names yes)"
          "  (show-names no))")
    (list "the option's own line" '(bad-option 4)
          "(instrument gong gong-strokes G"
          "  (show-names maybe))")
    (list "a note after an option" '(bad-form 3)
          "(instrument gong gong-strokes G (show-names yes) P)")
    (list "options but no notes" '(bad-form 3)
          "(instrument gong gong-strokes (show-names yes))")
    (list "options come before the scale" '(bad-option 3)
          "(instrument gong no-such-strokes G (show-names 1))")
    (list "options come before the notes" '(unknown-option 3)
          "(instrument gong gong-strokes Q (tempo 2))"))))

;;; ------------------------------------------------------------------
;;; Check order (03-reader.md, "Error reporting", items 5 to 13)

(test-group "slice 3 check order"
  (for-each
   (match-lambda
     ((name expected str)
      (test-equal name expected
        (match (length expected)
          (2 (string-error str))
          (3 (error-kind+line+part str))
          (4 (error-fields str))))))
   (list
    ;; Item 5: use.
    (list "use, then the piece's part errors" '(note-out-of-range 3)
          (lines "(piece \"P\")" "(use gong-kebyar)" "(part p ugal 99)"))
    ;; Item 6: bad-form, in file order, before everything after it.
    (list "a part's bad-form comes before a scale's bad-degree" '(bad-form 3)
          (lines "(piece \"P\")" "(scale s (ding (colour x)))" "(part)"))
    (list "a group's bad-form comes before a duplicate definition" '(bad-form 4)
          (lines "(piece \"P\")" "(strokes g G)" "(strokes g G)" "(group \"G\")"))
    (list "a group's bad-form comes before a duplicate part" '(bad-form 4)
          (lines "(piece \"P\")" "(part a x 1)" "(part a x 1)" "(group 1 a)"))
    (list "bad-form in file order: group before scale" '(bad-form 2)
          (lines "(piece \"P\")" "(group 1 a)" "(scale)"))
    (list "bad-form in file order: scale before part" '(bad-form 2)
          (lines "(piece \"P\")" "(scale)" "(part p)"))
    ;; Item 7: duplicates, before scales and instruments.
    (list "a duplicate part comes before an instrument error"
          '(duplicate-definition 5)
          (lines "(piece \"P\")" "(scale s ding)" "(instrument x s foo1)"
                 "(part p x 1)" "(part p x 1)"))
    (list "a duplicate part comes before a bad degree" '(duplicate-definition 3)
          (lines "(piece \"P\")" "(part p x 1)" "(part p x 1)"
                 "(scale s (ding (colour x)))"))
    (list "duplicates in file order: part before instrument"
          '(duplicate-definition 5)
          (lines "(piece \"P\")" "(strokes g G)" "(part p x G)"
                 "(instrument x g G)" "(part p x G)" "(instrument x g G)"))
    ;; Item 9 before 10.
    (list "an instrument error comes before an earlier part's error"
          '(unknown-note 4)
          (lines "(piece \"P\")" "(strokes g G)" "(part p x 9)"
                 "(instrument x g K)"))
    (list "undefined-scale comes before undefined-instrument" '(undefined-scale 3)
          (lines "(piece \"P\")" "(part p nowhere 1)" "(instrument x s ding1)"))
    ;; Item 10: within a part, instrument then tokens left to right.
    (list "undefined-instrument comes before the part's token errors"
          '(undefined-instrument 10 p)
          (defs+ "(part p nowhere \"x\" _)"))
    (list "unknown-note before a later out-of-range"
          '(unknown-note 10 p 1)
          (defs+ "(part p reyong 1 foo1 9 _)"))
    (list "out-of-range before a later unknown-note"
          '(note-out-of-range 10 p 1)
          (defs+ "(part p reyong 1 9 foo1)"))
    (list "hold-without-note before a later unknown-token"
          '(hold-without-note 10 p 1)
          (defs+ "(part p reyong - _ \"x\")"))
    (list "unknown-token before a later bad-chord"
          '(unknown-token 10 p 1)
          (defs+ "(part p reyong 1 \"x\" (1))"))
    (list "bad-chord before a later unknown-token"
          '(bad-chord 10 p 1)
          (defs+ "(part p reyong 1 (1) \"x\")"))
    ;; Item 10: parts in file order.
    (list "an earlier part's token error before a later part's"
          '(note-out-of-range 10 a 2)
          (defs+ "(part a reyong 1 2 9)" "(part b reyong foo1 1 2)"))
    (list "an earlier part's undefined-instrument before a later token error"
          '(undefined-instrument 10 a)
          (defs+ "(part a nowhere 1)" "(part b reyong 9)"))
    (list "an earlier part's token error before a later undefined-instrument"
          '(note-out-of-range 10 a 0)
          (defs+ "(part a reyong 9)" "(part b nowhere 1)"))
    ;; Item 10 before 11.
    (list "all parts' token errors come before unequal-length"
          '(note-out-of-range 12 c 3)
          (defs+ "(part a reyong 1 2 3 4)" "(part b reyong 1 2)"
                 "(part c reyong 1 2 3 9)"))
    (list "a later undefined-instrument comes before unequal-length"
          '(undefined-instrument 12 c)
          (defs+ "(part a reyong 1 2)" "(part b reyong 1)"
                 "(part c nowhere 1 2)"))
    ;; Item 11 before 12.
    (list "unequal-length comes before an earlier group's undefined-part"
          '(unequal-length 12 b #f)
          (defs+ "(group \"G\" nope)" "(part a reyong 1 2)" "(part b reyong 1)"))
    (list "unequal-length comes before a group option error"
          '(unequal-length 11 b #f)
          (defs+ "(part a reyong 1 2)" "(part b reyong 1)"
                 "(group \"G\" a (colour \"x\"))"))
    (list "unequal-length comes before mixed-pitched-group"
          '(unequal-length 11 u #f)
          (defs+ "(part a reyong 1 2)" "(part u ugal 1)" "(group \"G\" a u)"))
    ;; Item 12: within a group, options, then part names, then instruments.
    (list "a group's options come before its undefined part" '(unknown-option 11)
          (defs+ "(part a reyong 1)" "(group \"G\" nope (colour \"x\"))"))
    (list "a group's options come before mixed-pitched-group" '(bad-option 12)
          (defs+ "(part a reyong 1)" "(part u ugal 1)"
                 "(group \"G\" a u (subtitle 5))"))
    (list "part names in order: the first undefined one"
          '(undefined-part 11 nope1)
          (defs+ "(part a reyong 1)" "(group \"G\" nope1 nope2)"))
    (list "part names in order: part-in-two-groups before a later undefined"
          '(part-in-two-groups 12 a)
          (defs+ "(part a reyong 1)" "(group \"G1\" a)" "(group \"G2\" a nope)"))
    (list "part names in order: undefined before a later part-in-two-groups"
          '(undefined-part 12 nope)
          (defs+ "(part a reyong 1)" "(group \"G1\" a)" "(group \"G2\" nope a)"))
    (list "part names come before mixed-pitched-group"
          '(undefined-part 12 nope)
          (defs+ "(part a reyong 1)" "(part u ugal 1)" "(group \"G\" a u nope)"))
    ;; Item 12: groups in file order.
    (list "an earlier group's mixed-pitched-group before a later group's error"
          '(mixed-pitched-group 12 u)
          (defs+ "(part a reyong 1)" "(part u ugal 1)"
                 "(group \"G1\" a u)" "(group \"G2\" nope)"))
    (list "an earlier group's undefined-part before a later group's error"
          '(undefined-part 12 nope)
          (defs+ "(part a reyong 1)" "(part u ugal 1)"
                 "(group \"G1\" nope)" "(group \"G2\" a u)"))
    (list "an earlier group's option error before a later group's"
          '(unknown-option 12)
          (defs+ "(part a reyong 1)" "(part b reyong 1)"
                 "(group \"G1\" a (colour \"x\"))" "(group \"G2\" nope)"))
    ;; Item 13: text comes last.
    (list "token errors come before an earlier text" '(note-out-of-range 11 a 0)
          (defs+ "(text \"x\")" "(part a reyong 9)"))
    (list "unequal-length comes before an earlier text" '(unequal-length 12 b #f)
          (defs+ "(text \"x\")" "(part a reyong 1)" "(part b reyong 1 2)"))
    (list "group errors come before an earlier text" '(undefined-part 12)
          (defs+ "(text \"x\")" "(part a reyong 1)" "(group \"G\" nope)"))
    (list "valid parts and groups, then a text: not-implemented at the text"
          '(not-implemented 13)
          (defs+ "(part a reyong 1)" "(part b reyong 2)" "(group \"G\" a b)"
                 "(text \"x\")")))))

(test-group "slice 3: cases decided at review"
  ;; reyong has 8 notes; ugal has 6.
  (token-tests 'bad-chord
   (list (list "#t inside a chord" "reyong" "1 (2 #t) 3 4" 1)
         (list "1.5 inside a chord" "reyong" "1 (2 1.5) 3 4" 1)
         (list "a chord with one out-of-range note: bad-chord first"
               "reyong" "1 (9) 3 4" 1)))
  (test-equal "a part listed twice in one group: part-in-two-groups"
    '(part-in-two-groups 11 a)
    (error-kind+line+part
     (defs+ "(part a gong G P)" "(group \"G\" a a)")))
  (let ((pc (read-defs+ "(part a gong / /)")))
    (test-equal "a part of only / is allowed: length 0" 0
      (and pc (piece-length pc)))
    (test-equal "a part of only / has no events" '()
      (and pc (part-triples pc 'a)))))

;;; ==================================================================
;;; Slice 4: templates (`use`)
;;; ==================================================================
;;;
;;; Written from 03-reader.md ("Public interface", step 3, "Error
;;; reporting" item 5, the [4] error cases, "Slices" item 4) and
;;; 01-notation.md ("(use TEMPLATE)"). Template files are written at
;;; test time into a fresh temporary folder per case; `(use NAME)` tests
;;; put a templates/ folder there and prepend it to %load-path.

;;; ------------------------------------------------------------------
;;; Helpers for slice 4

(define tpl-root
  (mkdtemp (string-append (or (getenv "TMPDIR") "/tmp") "/notasi-tpl-XXXXXX")))

(define (fresh-dir)
  "A new empty folder for one test case, so file names never clash."
  (mkdtemp (string-append tpl-root "/case-XXXXXX")))

(define (mkdir-p path)
  (unless (file-exists? path)
    (mkdir-p (dirname path))
    (mkdir path)))

(define (put-file dir rel . strs)
  "Write the lines STRS to DIR/REL, creating folders, and return the path."
  (let ((path (string-append dir "/" rel)))
    (mkdir-p (dirname path))
    (call-with-output-file path
      (lambda (port) (display (apply lines strs) port)))
    path))

(define (remove-tpl-root)
  (system* "rm" "-rf" tpl-root))

(define (with-load-path dir thunk)
  "Run THUNK with DIR in front of %load-path, restoring it afterwards."
  (let ((saved #f))
    (dynamic-wind
      (lambda () (set! saved %load-path) (set! %load-path (cons dir saved)))
      thunk
      (lambda () (set! %load-path saved)))))

(define (with-cwd dir thunk)
  "Run THUNK with DIR as the current directory, restoring it afterwards."
  (let ((saved #f))
    (dynamic-wind
      (lambda () (set! saved (getcwd)) (chdir dir))
      thunk
      (lambda () (chdir saved)))))

(define (canon file)
  "FILE canonicalized, so paths joined in different ways compare equal.
#f stays #f; a path that doesn't exist is returned unchanged."
  (and file (or (false-if-exception (canonicalize-path file)) file)))

(define (err-at thunk)
  "(KIND FILE LINE) of the &notasi-syntax-error THUNK raises, with FILE
canonicalized, or the raised object (or no-error) unchanged."
  (let ((c (catch-syntax-error thunk)))
    (if (notasi-syntax-error? c)
        (list (notasi-syntax-error-kind c)
              (canon (notasi-syntax-error-file c))
              (notasi-syntax-error-line c))
        c)))

(define (at kind file line)
  "The expected (KIND FILE LINE), FILE canonicalized as in err-at."
  (list kind (canon file) line))

(define (string-in dir . strs)
  "A thunk that reads the lines STRS with read-piece-string, #:directory DIR."
  (lambda () (read-piece-string (apply lines strs) #:directory dir)))

(define (read-in dir . strs)
  "Read the lines STRS with #:directory DIR, or #f if reading raises."
  (try-read (apply string-in dir strs)))

(define (file-thunk path) (lambda () (read-piece-file path)))

(define (read-file path) (try-read (file-thunk path)))

(define (loc-of x)
  (cond ((scale? x) (scale-location x))
        ((degree? x) (degree-location x))
        ((instrument? x) (instrument-location x))
        ((part? x) (part-location x))
        ((group? x) (group-location x))
        (else (error "no location:" x))))

(define (file+line x)
  "(FILE LINE) of X's source location, FILE canonicalized."
  (let ((loc (loc-of x)))
    (list (canon (source-location-file loc)) (source-location-line loc))))

(define (scale-names pc) (map scale-name (piece-scales pc)))
(define (instrument-names pc) (map instrument-name (piece-instruments pc)))
(define (degree-names sc) (map degree-name (scale-degrees sc)))
(define (note-names inst) (map note-name (vector->list (instrument-notes inst))))

(define (error-tests cases)
  "CASES is a list of (NAME EXPECTED THUNK): check (err-at THUNK)."
  (for-each
   (match-lambda
     ((name expected thunk) (test-equal name expected (err-at thunk))))
   cases))

;;; ------------------------------------------------------------------
;;; Finding templates ("Public interface")

(test-group "templates: finding by name"
  ;; (use NAME) searches %load-path for templates/NAME.nts.
  (let* ((root (fresh-dir))
         (tpl (put-file root "templates/tfind.nts"
                        ";; a template"              ; 1
                        "(scale tfind-s a b)"        ; 2
                        "(instrument tfind-i tfind-s a1 b1)")) ; 3
         (pc (with-load-path root
               (lambda () (try-read-string "(piece \"P\")" "(use tfind)")))))
    (test-equal "use NAME loads templates/NAME.nts from %load-path" '(tfind-s)
      (scale-names pc))
    (test-equal "use NAME: instruments too" '(tfind-i)
      (instrument-names pc))
    (test-equal "use NAME: the scale's file is where it was found, and its line"
      (list (canon tpl) 2)
      (file+line (car (piece-scales pc))))
    (test-equal "use NAME: bare degrees have their scale's file and line"
      (list (list (canon tpl) 2) (list (canon tpl) 2))
      (map file+line (scale-degrees (car (piece-scales pc)))))
    (test-equal "use NAME: the instrument's file and line"
      (list (canon tpl) 3)
      (file+line (car (piece-instruments pc)))))

  ;; The first %load-path entry that has the template wins.
  (let* ((first (fresh-dir))
         (second (fresh-dir)))
    (put-file first "templates/tfirst.nts" "(scale first-s a)")
    (put-file second "templates/tfirst.nts" "(scale second-s a)")
    (test-equal "the first %load-path entry with the template is used"
      '(first-s)
      (with-load-path second
        (lambda ()
          (with-load-path first
            (lambda ()
              (scale-names (try-read-string "(piece \"P\")" "(use tfirst)"))))))))

  ;; A name is not looked up relative to the file or #:directory.
  (let ((dir (fresh-dir)))
    (put-file dir "tnear.nts" "(scale near-s a)")
    (put-file dir "templates/tnear2.nts" "(scale near2-s a)")
    (error-tests
     (list
      (list "use NAME does not look in #:directory itself"
            (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use tnear)"))
      (list "use NAME does not look in #:directory's templates/ unless on %load-path"
            (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use tnear2)")))))

  ;; The repository's templates/ folder, found with -L .
  (let ((pc (try-read-string "(piece \"P\")" "(use selisir)")))
    (test-equal "use selisir: the repo template" '(selisir)
      (scale-names pc))
    (test-equal "use selisir: file is templates/selisir.nts"
      '("templates" "selisir.nts")
      (let ((f (source-location-file (scale-location (car (piece-scales pc))))))
        (list (basename (dirname f)) (basename f))))
    (test-equal "use selisir: scale line" 5
      (source-location-line (scale-location (car (piece-scales pc)))))
    (test-equal "use selisir: degree lines" '(6 7 8 9 10)
      (map (lambda (d) (source-location-line (degree-location d)))
           (scale-degrees (car (piece-scales pc)))))
    (test-equal "use selisir: degree files are the template's"
      '("selisir.nts" "selisir.nts" "selisir.nts" "selisir.nts" "selisir.nts")
      (map (lambda (d) (basename (source-location-file (degree-location d))))
           (scale-degrees (car (piece-scales pc)))))
    (test-equal "use selisir: aliases work in the piece's instrument"
      '(ding2 dong2)
      (note-names (car (piece-instruments
                        (try-read-string "(piece \"P\")" "(use selisir)"
                                         "(instrument x selisir i2 o2)")))))))

(test-group "templates: finding by string"
  ;; read-piece-file: relative to the piece file's folder.
  (let* ((dir (fresh-dir))
         (tpl (put-file dir "defs.nts" ";; defs" "(scale sdefs a b)"))
         (piece (put-file dir "piece.nts"
                          "(piece \"P\")"                  ; 1
                          "(use \"defs.nts\")"             ; 2
                          "(instrument x sdefs a1 b1)"     ; 3
                          "(part p x 1 2)"))               ; 4
         (pc (read-file piece)))
    (test-equal "read-piece-file: string relative to the piece's folder"
      '(sdefs) (scale-names pc))
    (test-equal "read-piece-file: template scale's file and line"
      (list (canon tpl) 2) (file+line (car (piece-scales pc))))
    (test-equal "read-piece-file: piece's own instrument has the piece's file"
      (list (canon piece) 3) (file+line (car (piece-instruments pc))))
    (test-equal "read-piece-file: piece's part has the piece's file"
      (list (canon piece) 4) (file+line (car (piece-parts pc)))))

  ;; A string in a template is relative to that template's folder.
  (let* ((dir (fresh-dir))
         (more (put-file dir "sub/more.nts" "(scale sub-more a)")))
    (put-file dir "more.nts" "(scale decoy-more a)")
    (put-file dir "sub/defs.nts" "(use \"more.nts\")" "(scale sub-defs a)")
    (let* ((piece (put-file dir "piece.nts" "(piece \"P\")" "(use \"sub/defs.nts\")"))
           (pc (read-file piece)))
      (test-equal "a string in a subfolder, and a string in a template is relative to the template"
        '(sub-more sub-defs) (scale-names pc))
      (test-equal "sub/more.nts's location"
        (list (canon more) 1) (file+line (car (piece-scales pc))))))

  ;; read-piece-string and read-piece-port: #:directory.
  (let* ((dir (fresh-dir))
         (tpl (put-file dir "defs.nts" "(scale sdir a)")))
    (let ((pc (read-in dir "(piece \"P\")" "(use \"defs.nts\")")))
      (test-equal "read-piece-string: relative to #:directory" '(sdir)
        (scale-names pc))
      (test-equal "read-piece-string: template file is #:directory joined with the string"
        (list (canon tpl) 1) (file+line (car (piece-scales pc)))))
    (let ((pc (try-read
               (lambda ()
                 (call-with-input-string (lines "(piece \"P\")" "(use \"defs.nts\")")
                   (lambda (p) (read-piece-port p #:directory dir)))))))
      (test-equal "read-piece-port: relative to #:directory" '(sdir)
        (scale-names pc))
      (test-equal "read-piece-port: template file"
        (list (canon tpl) 1) (file+line (car (piece-scales pc)))))
    (let ((pc (read-in dir "(piece \"P\")" "(use \"defs.nts\")" "(scale own a)")))
      (test-equal "read-piece-string: the piece's own definitions have file #f"
        '(#f 3) (file+line (cadr (piece-scales pc))))))

  ;; No #:directory: the current directory.
  (let* ((dir (fresh-dir))
         (tpl (put-file dir "cwd-defs.nts" "(scale scwd a)")))
    (test-equal "read-piece-string without #:directory: current directory"
      (list '(scwd) (list (canon tpl) 1))
      (with-cwd dir
        (lambda ()
          (let ((pc (try-read-string "(piece \"P\")" "(use \"cwd-defs.nts\")")))
            (list (scale-names pc) (file+line (car (piece-scales pc))))))))
    (test-equal "read-piece-port without #:directory: current directory"
      '(scwd)
      (with-cwd dir
        (lambda ()
          (scale-names
           (try-read
            (lambda ()
              (call-with-input-string
                  (lines "(piece \"P\")" "(use \"cwd-defs.nts\")")
                read-piece-port))))))))

  ;; A name inside a string-found template still uses %load-path, and a
  ;; string inside a name-found template is relative to templates/.
  (let ((dir (fresh-dir)))
    (put-file dir "defs.nts" "(use selisir)" "(instrument x selisir i1 o1)")
    (let ((pc (read-in dir "(piece \"P\")" "(use \"defs.nts\")")))
      (test-equal "a name in a string-found template: scales" '(selisir)
        (scale-names pc))
      (test-equal "a name in a string-found template: instruments" '(x)
        (instrument-names pc))))
  (let* ((root (fresh-dir))
         (other (fresh-dir)))
    (put-file root "templates/tnest.nts" "(use \"tnest-part.nts\")" "(scale tnest a)")
    (put-file root "templates/tnest-part.nts" "(scale tnest-part a)")
    (put-file other "tnest-part.nts" "(scale decoy a)")
    (test-equal "a string in a name-found template is relative to its templates/ folder"
      '(tnest-part tnest)
      (with-load-path root
        (lambda ()
          (scale-names (read-in other "(piece \"P\")" "(use tnest)")))))))

(test-group "templates: the same template reached twice"
  ;; Two uses reach the same template when the canonical paths are equal.
  (let ((dir (fresh-dir)))
    (put-file dir "defs.nts" "(scale sdefs a)" "(instrument idefs sdefs a1)")
    (mkdir-p (string-append dir "/sub"))
    (let ((pc (read-in dir "(piece \"P\")" "(use \"defs.nts\")" "(use \"defs.nts\")")))
      (test-equal "same use twice: scales once" '(sdefs) (scale-names pc))
      (test-equal "same use twice: instruments once" '(idefs) (instrument-names pc)))
    (let ((pc (read-in dir "(piece \"P\")" "(use \"defs.nts\")" "(use \"./defs.nts\")"
                       "(use \"sub/../defs.nts\")")))
      (test-equal "different spellings of one path: scales once" '(sdefs)
        (scale-names pc))
      (test-equal "different spellings of one path: instruments once" '(idefs)
        (instrument-names pc))))
  (let ((root (fresh-dir)))
    (put-file root "templates/tsame.nts" "(scale tsame a)")
    (test-equal "a name and a string reaching the same file: once" '(tsame)
      (with-load-path root
        (lambda ()
          (scale-names (read-in root "(piece \"P\")" "(use tsame)"
                                "(use \"templates/tsame.nts\")"))))))
  (let ((pc (try-read-string "(piece \"P\")" "(use selisir)" "(use selisir)")))
    (test-equal "use selisir twice" '(selisir) (scale-names pc))))

;;; ------------------------------------------------------------------
;;; Merging definitions (step 3)

(test-group "templates: merged order"
  ;; Depth-first load order; a template's definitions after those of
  ;; the templates it uses; the piece's own last.
  (let ((dir (fresh-dir)))
    (put-file dir "c.nts" "(scale sc x)" "(instrument ic sc x1)")
    (put-file dir "a.nts" "(use \"c.nts\")" "(scale sa x)" "(instrument ia sa x1)")
    (put-file dir "b.nts" "(scale sb x)" "(instrument ib sb x1)")
    (let ((pc (read-in dir "(piece \"P\")" "(use \"a.nts\")" "(use \"b.nts\")"
                       "(instrument ip sp x1)" "(scale sp x)")))
      (test-equal "scales: depth-first, piece last" '(sc sa sb sp)
        (scale-names pc))
      (test-equal "instruments: depth-first, piece last" '(ic ia ib ip)
        (instrument-names pc))
      (test-equal "each scale's file and line"
        (list (list (canon (string-append dir "/c.nts")) 1)
              (list (canon (string-append dir "/a.nts")) 2)
              (list (canon (string-append dir "/b.nts")) 1)
              (list #f 5))
        (map file+line (piece-scales pc)))
      (test-equal "each instrument's file and line"
        (list (list (canon (string-append dir "/c.nts")) 2)
              (list (canon (string-append dir "/a.nts")) 3)
              (list (canon (string-append dir "/b.nts")) 2)
              (list #f 4))
        (map file+line (piece-instruments pc)))))

  ;; gong-kebyar uses selisir: the real templates.
  (let ((pc (try-read-string "(piece \"P\")" "(use gong-kebyar)")))
    (test-equal "gong-kebyar: scales in load order"
      '(selisir kempli-strokes gong-strokes kendang-strokes)
      (scale-names pc))
    (test-equal "gong-kebyar: instruments in load order"
      '(ugal reyong kempli gong kendang)
      (instrument-names pc))
    (test-equal "gong-kebyar: files"
      '("selisir.nts" "gong-kebyar.nts" "gong-kebyar.nts" "gong-kebyar.nts")
      (map (lambda (s) (basename (source-location-file (scale-location s))))
           (piece-scales pc)))
    (test-equal "gong-kebyar: instrument lines" '(14 17 21 22 23)
      (map (lambda (i) (source-location-line (instrument-location i)))
           (piece-instruments pc)))
    (test-equal "gong-kebyar: ugal notes resolve against selisir"
      '(dong1 deng1 dung1 dang1 ding2 dong2 deng2 dung2 dang2 ding3)
      (note-names (instrument-named pc 'ugal)))
    (test-assert "gong-kebyar: ugal's scale is the merged selisir"
      (eq? (instrument-scale (instrument-named pc 'ugal))
           (scale-named pc 'selisir))))

  ;; A template reached twice contributes once, at its first place.
  (let ((pc (try-read-string "(piece \"P\")" "(use gong-kebyar)" "(use selisir)")))
    (test-equal "selisir via gong-kebyar and directly: once, at its first place"
      '(selisir kempli-strokes gong-strokes kendang-strokes)
      (scale-names pc)))
  (let ((dir (fresh-dir)))
    (put-file dir "d.nts" "(scale sd a)")
    (put-file dir "b.nts" "(use \"d.nts\")" "(scale sb a)")
    (put-file dir "c.nts" "(use \"./d.nts\")" "(scale sc a)")
    (test-equal "diamond (b and c both use d): d once, first, no conflict"
      '(sd sb sc)
      (scale-names (read-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")")))
    (test-equal "diamond with d also used directly afterwards: still at its first place"
      '(sd sb sc)
      (scale-names (read-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")"
                            "(use \"d.nts\")")))))

(test-group "templates: replacing definitions"
  ;; The piece replaces a scale and an instrument: removed from their
  ;; earlier place, the replacement where the piece puts it.
  (let ((dir (fresh-dir)))
    (put-file dir "t.nts"
              "(scale s1 x)" "(scale s2 x)" "(scale s3 x)"
              "(instrument i1 s1 x1)" "(instrument i2 s2 x1)" "(instrument i3 s3 x1)")
    (let ((pc (read-in dir "(piece \"P\")" "(use \"t.nts\")"
                       "(instrument i2 s1 x1)"     ; 3
                       "(scale s2 y)")))           ; 4
      (test-equal "a replaced scale moves to the piece's place" '(s1 s3 s2)
        (scale-names pc))
      (test-equal "a replaced instrument moves to the piece's place" '(i1 i3 i2)
        (instrument-names pc))
      (test-equal "the replacement scale is the piece's" '(y)
        (degree-names (scale-named pc 's2)))
      (test-equal "the replacement scale's location" '(#f 4)
        (file+line (scale-named pc 's2)))
      (test-equal "the replacement instrument's scale" 's1
        (scale-name (instrument-scale (instrument-named pc 'i2))))
      (test-equal "the replacement instrument's location" '(#f 3)
        (file+line (instrument-named pc 'i2)))
      (test-equal "the template's i2 is gone: one instrument named i2" 1
        (count (lambda (i) (eq? (instrument-name i) 'i2)) (piece-instruments pc)))))

  ;; Names are resolved after merging: a template instrument whose notes
  ;; only exist on the piece's replacement scale.
  (let* ((dir (fresh-dir))
         (t-path (put-file dir "t.nts" "(scale s a b)" "(instrument x s a1 c1)")))
    (test-equal "without the replacement: unknown-note in the template"
      (at 'unknown-note t-path 2)
      (err-at (string-in dir "(piece \"P\")" "(use \"t.nts\")")))
    (let ((pc (read-in dir "(piece \"P\")" "(use \"t.nts\")" "(scale s a b c)")))
      (test-equal "with the replacement: the template instrument resolves against it"
        '(a1 c1) (note-names (instrument-named pc 'x)))
      (test-assert "the template instrument's scale is the replacement record"
        (eq? (instrument-scale (instrument-named pc 'x)) (scale-named pc 's)))
      (test-equal "the template instrument keeps the template's location"
        (list (canon t-path) 2) (file+line (instrument-named pc 'x)))))

  ;; The real gong-kebyar: replace ugal's range.
  (let ((pc (try-read-string "(piece \"P\")" "(use gong-kebyar)"
                             "(instrument ugal selisir i2 o2 e2)"   ; 3
                             "(part p ugal 1 2 3)")))               ; 4
    (test-equal "replacing ugal: it moves to the end" '(reyong kempli gong kendang ugal)
      (instrument-names pc))
    (test-equal "replacing ugal: the piece's notes" '(ding2 dong2 deng2)
      (note-names (instrument-named pc 'ugal)))
    (test-equal "replacing ugal: location" '(#f 3)
      (file+line (instrument-named pc 'ugal)))
    (test-assert "replacing ugal: the part plays the replacement"
      (eq? (part-instrument (part-named pc 'p)) (instrument-named pc 'ugal))))
  (test-equal "replacing ugal: the template's 10 notes are gone"
    '(note-out-of-range 4 p 0)
    (error-fields (lines "(piece \"P\")" "(use gong-kebyar)"
                         "(instrument ugal selisir i2 o2 e2)" "(part p ugal 4)")))

  ;; A template replaces its own template's definitions.
  (let ((dir (fresh-dir)))
    (put-file dir "d.nts" "(scale s a)" "(instrument x s a1)")
    (let ((m (put-file dir "m.nts" "(use \"d.nts\")" "(scale s a b)")))
      (let ((pc (read-in dir "(piece \"P\")" "(use \"m.nts\")")))
        (test-equal "a template's own definition replaces its template's" '(s)
          (scale-names pc))
        (test-equal "the replacing scale is the template's own" '(a b)
          (degree-names (scale-named pc 's)))
        (test-equal "the replacing scale's location" (list (canon m) 2)
          (file+line (scale-named pc 's)))
        (test-equal "d's instrument uses m's scale" '(a b)
          (degree-names (instrument-scale (instrument-named pc 'x))))))))

(test-group "templates: no conflict"
  (let ((dir (fresh-dir)))
    (put-file dir "b.nts" "(scale s a)")
    (put-file dir "c.nts" "(scale s b)")
    (put-file dir "m.nts" "(use \"b.nts\")" "(use \"c.nts\")" "(scale s m)")
    (let ((pc (read-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")"
                       "(scale s c)")))
      (test-equal "the piece's own definition resolves a would-be conflict" '(s)
        (scale-names pc))
      (test-equal "the piece's definition is the one kept" '(c)
        (degree-names (scale-named pc 's)))
      (test-equal "and its location" '(#f 4) (file+line (scale-named pc 's))))
    (test-equal "a template's own definition resolves its templates' conflict" '(m)
      (degree-names
       (scale-named (read-in dir "(piece \"P\")" "(use \"m.nts\")") 's))))
  (let ((dir (fresh-dir)))
    (put-file dir "b.nts" "(scale s a)" "(instrument i s a1)")
    (put-file dir "c.nts" "(strokes i K)")
    (let ((pc (read-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")")))
      (test-equal "an instrument and a stroke set of the same name don't conflict: scales"
        '(s i) (scale-names pc))
      (test-equal "an instrument and a stroke set of the same name don't conflict: instruments"
        '(i) (instrument-names pc)))))

;;; ------------------------------------------------------------------
;;; Error cases [4]

(test-group "template-not-found"
  (let* ((dir (fresh-dir))
         (t (put-file dir "t.nts" ";; t" "(use \"nope.nts\")"))
         (piece (put-file dir "piece.nts" "(piece \"P\")" "" "(use \"nope.nts\")"))
         (piece2 (put-file dir "piece2.nts" "(piece \"P\")" "(use \"t.nts\")")))
    (error-tests
     (list
      (list "a string that doesn't exist" (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use \"nope.nts\")"))
      (list "a name that doesn't exist" (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use notasi-test-no-such-template)"))
      (list "from a file: the piece's file and the use's line"
            (at 'template-not-found piece 3) (file-thunk piece))
      (list "inside a template: the template's file and line"
            (at 'template-not-found t 2)
            (string-in dir "(piece \"P\")" "(use \"t.nts\")"))
      (list "inside a template, the piece read from a file"
            (at 'template-not-found t 2) (file-thunk piece2))
      (list "a string relative to #:directory, not the current directory"
            (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use \"tests/reader.scm\")"))))
    (let ((c (catch-syntax-error (string-in dir "(piece \"P\")" "(use \"nope.nts\")"))))
      (test-equal "kind, part field #f, step field #f" '(template-not-found #f #f)
        (and (notasi-syntax-error? c)
             (list (notasi-syntax-error-kind c) (notasi-syntax-error-part c)
                   (notasi-syntax-error-step c)))))))

(test-group "template-cycle"
  (let* ((dir (fresh-dir))
         (self (put-file dir "self.nts" ";; self" "(use \"self.nts\")"))
         (self2 (put-file dir "self2.nts" "(use \"./self2.nts\")"))
         (a (put-file dir "a.nts" "(use \"b.nts\")" "(scale sa x)"))
         (b (put-file dir "b.nts" ";; b" "(use \"a.nts\")"))
         (piece (put-file dir "piece.nts" "(piece \"P\")" "(use \"piece.nts\")")))
    (error-tests
     (list
      (list "a template using itself" (at 'template-cycle self 2)
            (string-in dir "(piece \"P\")" "(use \"self.nts\")"))
      (list "a template using itself, spelled differently"
            (at 'template-cycle self2 1)
            (string-in dir "(piece \"P\")" "(use \"self2.nts\")"))
      (list "a uses b, b uses a: at b's use" (at 'template-cycle b 2)
            (string-in dir "(piece \"P\")" "(use \"a.nts\")"))
      (list "b uses a, a uses b: at a's use" (at 'template-cycle a 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")"))
      (list "the piece file using itself" (at 'template-cycle piece 2)
            (file-thunk piece)))))
  (let ((root (fresh-dir)))
    (put-file root "templates/cyc-a.nts" "(use cyc-b)")
    (put-file root "templates/cyc-b.nts" "(use cyc-c)")
    (let ((c (put-file root "templates/cyc-c.nts" ";; c" ";; c" "(use cyc-a)")))
      (test-equal "a three-template cycle by name: at the use that closes it"
        (at 'template-cycle c 3)
        (with-load-path root
          (lambda ()
            (err-at (lambda () (read-piece-string
                                (lines "(piece \"P\")" "(use cyc-a)")))))))))
  (let* ((dir (fresh-dir))
         (t1 (put-file dir "t1.nts" "(use \"t1.nts\")" "(use \"nope.nts\")"))
         (t2 (put-file dir "t2.nts" "(use \"nope.nts\")" "(use \"t2.nts\")")))
    (error-tests
     (list
      (list "a cycle at an earlier use before a later not-found"
            (at 'template-cycle t1 1)
            (string-in dir "(piece \"P\")" "(use \"t1.nts\")"))
      (list "a not-found at an earlier use before a later cycle"
            (at 'template-not-found t2 1)
            (string-in dir "(piece \"P\")" "(use \"t2.nts\")"))))))

(test-group "bad-form of a use"
  (let ((dir (fresh-dir)))
    (error-tests
     (map (match-lambda
            ((name form)
             (list name (at 'bad-form #f 3)
                   (string-in dir "(piece \"P\")" ";; c" form))))
          (list (list "(use)" "(use)")
                (list "(use 42)" "(use 42)")
                (list "(use a b)" "(use a b)")
                (list "two strings" "(use \"a.nts\" \"b.nts\")")
                (list "(use #t)" "(use #t)")
                (list "a list" "(use (selisir))"))))
    (let ((t (put-file dir "t.nts" ";; t" "(use 42)")))
      (test-equal "in a template: the template's file and line"
        (at 'bad-form t 2)
        (err-at (string-in dir "(piece \"P\")" "(use \"t.nts\")"))))))

(test-group "not-in-template"
  (let ((dir (fresh-dir)))
    (error-tests
     (map (match-lambda
            ((name form)
             (let ((t (put-file dir (string-append name ".nts")
                                "(scale s a)" form "(scale s2 a)")))
               (list (string-append name " in a template") (at 'not-in-template t 2)
                     (string-in dir "(piece \"P\")"
                                (string-append "(use \"" name ".nts\")"))))))
          (list (list "piece" "(piece \"T\")")
                (list "part" "(part p x 1)")
                (list "group" "(group \"G\" p)")
                (list "text" "(text \"x\")"))))
    (let ((t (put-file dir "two.nts" "(scale s a)" "(group \"G\" p)" "(part p x 1)")))
      (test-equal "the first such form in file order" (at 'not-in-template t 2)
        (err-at (string-in dir "(piece \"P\")" "(use \"two.nts\")"))))))

(test-group "use-not-first"
  (let ((dir (fresh-dir)))
    (put-file dir "t.nts" "(scale ts a)")
    (error-tests
     (list
      (list "after a scale" (at 'use-not-first #f 3)
            (string-in dir "(piece \"P\")" "(scale s a)" "(use \"t.nts\")"))
      (list "after a stroke set" (at 'use-not-first #f 3)
            (string-in dir "(piece \"P\")" "(strokes k K)" "(use \"t.nts\")"))
      (list "after an instrument" (at 'use-not-first #f 4)
            (string-in dir "(piece \"P\")" "(use \"t.nts\")"
                       "(instrument x ts a1)" "(use \"t.nts\")"))
      (list "after a part" (at 'use-not-first #f 3)
            (string-in dir "(piece \"P\")" "(part p x 1)" "(use \"t.nts\")"))
      (list "after a group" (at 'use-not-first #f 3)
            (string-in dir "(piece \"P\")" "(group \"G\" p)" "(use \"t.nts\")"))
      (list "the first late use" (at 'use-not-first #f 4)
            (string-in dir "(piece \"P\")" "(use \"t.nts\")" "(scale s a)"
                       "(use \"t.nts\")" "(use \"t.nts\")"))))
    (test-assert "several uses right after piece are fine"
      (piece? (read-in dir "(piece \"P\")" "(use \"t.nts\")" "(use selisir)"
                       "(scale s a)")))
    (let ((t (put-file dir "late.nts" "(scale s a)" ";; c" "(use \"t.nts\")")))
      (test-equal "in a template: the template's file and line"
        (at 'use-not-first t 3)
        (err-at (string-in dir "(piece \"P\")" "(use \"late.nts\")"))))))

(test-group "template-conflict"
  (let* ((dir (fresh-dir))
         (b (put-file dir "b.nts" "(scale s a)"))
         (c (put-file dir "c.nts" ";; c" "(scale s b)"))
         (c-same (put-file dir "c-same.nts" "(scale s a)"))
         (c-strokes (put-file dir "c-strokes.nts" "(strokes s K)"))
         (bi (put-file dir "bi.nts" "(scale sb a)" "(instrument x sb a1)"))
         (ci (put-file dir "ci.nts" "(scale sc a)" "(instrument x sc a1)"))
         (e (put-file dir "e.nts" "(scale s e)"))
         (ce (put-file dir "ce.nts" "(use \"e.nts\")" "(scale other a)"))
         (cr (put-file dir "cr.nts" "(use \"e.nts\")" "(scale s r)"))
         (m (put-file dir "m.nts" "(use \"b.nts\")" "(use \"c.nts\")")))
    (error-tests
     (list
      (list "two templates define the same scale: at the second"
            (at 'template-conflict c 2)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")"))
      (list "the other use order: at the second in load order"
            (at 'template-conflict b 1)
            (string-in dir "(piece \"P\")" "(use \"c.nts\")" "(use \"b.nts\")"))
      (list "identical text in two files is still a conflict"
            (at 'template-conflict c-same 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c-same.nts\")"))
      (list "a scale and a stroke set share names"
            (at 'template-conflict c-strokes 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c-strokes.nts\")"))
      (list "two templates define the same instrument"
            (at 'template-conflict ci 2)
            (string-in dir "(piece \"P\")" "(use \"bi.nts\")" "(use \"ci.nts\")"))
      (list "a name a template gets from its own template conflicts too"
            (at 'template-conflict e 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"ce.nts\")"))
      (list "a template's replacement conflicts at its own definition"
            (at 'template-conflict cr 2)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"cr.nts\")"))
      (list "a conflict between a template's templates"
            (at 'template-conflict c 2)
            (string-in dir "(piece \"P\")" "(use \"m.nts\")"))))
    (let ((cnd (catch-syntax-error
                (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")"))))
      (test-assert "the message names the first definition's file"
        (and (notasi-syntax-error? cnd)
             (string-contains (exception-message cnd) "b.nts")))
      (test-equal "kind, part field #f, step field #f" '(template-conflict #f #f)
        (and (notasi-syntax-error? cnd)
             (list (notasi-syntax-error-kind cnd) (notasi-syntax-error-part cnd)
                   (notasi-syntax-error-step cnd))))))
  ;; With the real templates: my.nts also uses selisir (no conflict
  ;; there) but defines ugal, which gong-kebyar defines too.
  (let* ((dir (fresh-dir))
         (my (put-file dir "my.nts" "(use selisir)" "(instrument ugal selisir i2)")))
    (test-equal "ugal from gong-kebyar and from another template"
      (at 'template-conflict my 2)
      (err-at (string-in dir "(piece \"P\")" "(use gong-kebyar)" "(use \"my.nts\")")))))

(test-group "errors inside a template"
  (let* ((dir (fresh-dir))
         (t (lambda (name . strs)
              (apply put-file dir (string-append name ".nts") strs)))
         (use (lambda (name)
                (string-in dir "(piece \"P\")"
                           (string-append "(use \"" name ".nts\")")))))
    (let ((rd (t "rd" "(scale s a)" "(scale s2 b")))
      (test-equal "read-error: kind and file" (list 'read-error (canon rd))
        (list-head (err-at (use "rd")) 2))
      (test-assert "read-error: a line"
        (match (err-at (use "rd"))
          (('read-error _ line) (valid-guile-line? line))
          (_ #f))))
    (error-tests
     (list
      (list "improper-form" (at 'improper-form (t "imp" ";; x" "(scale s a . b)") 2)
            (use "imp"))
      (list "unknown-form" (at 'unknown-form (t "unk" "(scale s a)" "(foo)") 2)
            (use "unk"))
      (list "bad-form" (at 'bad-form (t "bf" "(scale s a)" "(instrument x)") 2)
            (use "bf"))
      (list "duplicate-definition"
            (at 'duplicate-definition (t "dup" "(scale s a)" "(strokes s K)") 2)
            (use "dup"))
      (list "bad-degree at the degree's own line"
            (at 'bad-degree (t "bd" "(scale s" "  a" "  (b (bogus 1)))") 3)
            (use "bd"))
      (list "degree-ends-in-digit"
            (at 'degree-ends-in-digit (t "dig" ";; x" "(scale s a1)") 2)
            (use "dig"))
      (list "duplicate-degree"
            (at 'duplicate-degree (t "dd" "(scale s a (b (alias a)))") 1)
            (use "dd"))
      (list "undefined-scale"
            (at 'undefined-scale (t "us" "(scale s a)" "(instrument x nosuch a1)") 2)
            (use "us"))
      (list "unknown-note"
            (at 'unknown-note (t "un" "(scale s a)" "" "(instrument x s b1)") 3)
            (use "un"))
      (list "notes-not-ascending"
            (at 'notes-not-ascending (t "na" "(scale s a b)" "(instrument x s b1 a1)") 2)
            (use "na"))
      (list "duplicate-note"
            (at 'duplicate-note (t "dn" "(strokes k K)" "(instrument x k K K)") 2)
            (use "dn"))
      (list "an error two templates deep"
            (at 'bad-form (t "deep2" "(scale)") 1)
            (begin (t "deep1" "(use \"deep2.nts\")") (use "deep1")))))
    (let* ((piece (put-file dir "piece.nts" "(piece \"P\")" "(use \"un.nts\")")))
      (test-equal "from a file: the template's file, not the piece's"
        (at 'unknown-note (string-append dir "/un.nts") 3)
        (err-at (file-thunk piece))))))

;;; ------------------------------------------------------------------
;;; Check order (03-reader.md "Error reporting", item 5)

(test-group "templates: check order"
  (let* ((dir (fresh-dir))
         (t (lambda (name . strs)
              (apply put-file dir (string-append name ".nts") strs)))
         (bf (t "bf" "(scale)"))                           ; bad-form at 1
         (dup (t "dup" "(scale s a)" "(scale s b)"))       ; duplicate at 2
         (q (t "q" "(instrument)"))                         ; bad-form at 1
         (m (t "m" "(use \"q.nts\")" "(scale)"))
         (late (t "late" "(use \"q.nts\")" "(scale s a)" "(use \"nope.nts\")"))
         (nit (t "nit" "(use \"nope.nts\")" "(part p x 1)"))
         (nit2 (t "nit2" "(use)" "(group \"G\" p)"))
         (nit3 (t "nit3" "(scale)" "(text \"x\")"))
         (unk (t "unk" "(part p x 1)" "(foo)"))
         (b (t "b" "(scale s a)"))
         (c (t "c" "(scale s b)"))
         (mc (t "mc" "(use \"b.nts\")" "(use \"c.nts\")"))
         (tdeg (t "tdeg" "(scale s (a (bogus 1)))"))
         (tnote (t "tnote" "(scale ts a)" "(instrument tx ts b1)"))
         (tus (t "tus" "(instrument tx nosuch a1)"))
         (tshape (t "tshape" "(scale s)")))
    (error-tests
     (list
      ;; Items 1-4 of the piece come before its templates.
      (list "unknown-form in the piece before template-not-found"
            (at 'unknown-form #f 4)
            (string-in dir "(piece \"P\")" "(use \"nope.nts\")" "(scale s a)" "(foo)"))
      (list "bad-title before template-not-found" (at 'bad-title #f 1)
            (string-in dir "(piece 1)" "(use \"nope.nts\")"))
      (list "bad-option before a template's error" (at 'bad-option #f 1)
            (string-in dir "(piece \"P\" (steps-per-pulse 0))" "(use \"bf.nts\")"))
      ;; 5.1: the piece's use forms before loading any template.
      (list "use-not-first before bad-form of an earlier use"
            (at 'use-not-first #f 4)
            (string-in dir "(piece \"P\")" "(use)" "(scale s a)" "(use \"bf.nts\")"))
      (list "use-not-first before template-not-found"
            (at 'use-not-first #f 4)
            (string-in dir "(piece \"P\")" "(use \"nope.nts\")" "(scale s a)"
                       "(use \"bf.nts\")"))
      (list "a later use's bad-form before an earlier use's template-not-found"
            (at 'bad-form #f 3)
            (string-in dir "(piece \"P\")" "(use \"nope.nts\")" "(use 42)"))
      (list "a later use's bad-form before an earlier template's error"
            (at 'bad-form #f 3)
            (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(use)"))
      ;; 5.2: templates in use order, depth-first.
      (list "the first use's template error first" (at 'bad-form bf 1)
            (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(use \"nope.nts\")"))
      (list "the first use's not-found first" (at 'template-not-found #f 2)
            (string-in dir "(piece \"P\")" "(use \"nope.nts\")" "(use \"bf.nts\")"))
      (list "depth-first: a template's template before the template's own forms"
            (at 'bad-form q 1)
            (string-in dir "(piece \"P\")" "(use \"m.nts\")"))
      (list "depth-first: a template's template before a later use"
            (at 'bad-form q 1)
            (string-in dir "(piece \"P\")" "(use \"m.nts\")" "(use \"dup.nts\")"))
      (list "in a template: use-not-first before loading its templates"
            (at 'use-not-first late 3)
            (string-in dir "(piece \"P\")" "(use \"late.nts\")"))
      (list "in a template: not-in-template before its use errors"
            (at 'not-in-template nit 2)
            (string-in dir "(piece \"P\")" "(use \"nit.nts\")"))
      (list "in a template: not-in-template before a use's bad-form"
            (at 'not-in-template nit2 2)
            (string-in dir "(piece \"P\")" "(use \"nit2.nts\")"))
      (list "in a template: not-in-template before bad-form of a definition"
            (at 'not-in-template nit3 2)
            (string-in dir "(piece \"P\")" "(use \"nit3.nts\")"))
      (list "in a template: unknown-form before not-in-template"
            (at 'unknown-form unk 2)
            (string-in dir "(piece \"P\")" "(use \"unk.nts\")"))
      ;; 5.3: a conflict after all of a file's templates are loaded.
      (list "a later template's error before a conflict between earlier ones"
            (at 'bad-form bf 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")"
                       "(use \"bf.nts\")"))
      (list "a conflict inside a template before a later use's error"
            (at 'template-conflict c 1)
            (string-in dir "(piece \"P\")" "(use \"mc.nts\")" "(use \"bf.nts\")"))
      ;; Templates before the piece's own items 6-13.
      (list "a template error before the piece's bad-form" (at 'duplicate-definition dup 2)
            (string-in dir "(piece \"P\")" "(use \"dup.nts\")" "(scale)"))
      (list "a template error before the piece's duplicate-definition"
            (at 'bad-form bf 1)
            (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(scale s a)" "(scale s b)"))
      (list "a template error before the piece's part errors"
            (at 'bad-form bf 1)
            (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(part p nope 1)"))
      (list "a template error before the piece's text"
            (at 'bad-form bf 1)
            (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(text \"x\")"))
      (list "template-conflict before the piece's bad-form"
            (at 'template-conflict c 1)
            (string-in dir "(piece \"P\")" "(use \"b.nts\")" "(use \"c.nts\")" "(part)"))
      ;; Items 8 and 9 run over the merged definitions, after item 6 of
      ;; the piece.
      (list "the piece's bad-form before a template's bad-degree"
            (at 'bad-form #f 3)
            (string-in dir "(piece \"P\")" "(use \"tdeg.nts\")" "(scale)"))
      (list "the piece's bad-degree before a template's unknown-note"
            (at 'bad-degree #f 3)
            (string-in dir "(piece \"P\")" "(use \"tnote.nts\")" "(scale s (a (bogus 1)))"))
      (list "the piece's degree-ends-in-digit before a template's undefined-scale"
            (at 'degree-ends-in-digit #f 3)
            (string-in dir "(piece \"P\")" "(use \"tus.nts\")" "(scale s a1)"))
      (list "a template's bad-degree before the piece's (merged order)"
            (at 'bad-degree tdeg 1)
            (string-in dir "(piece \"P\")" "(use \"tdeg.nts\")" "(scale s2 (b (bogus 1)))"))
      (list "a template's unknown-note before the piece's (merged order)"
            (at 'unknown-note tnote 2)
            (string-in dir "(piece \"P\")" "(use \"tnote.nts\")" "(scale s a)"
                       "(instrument x s b1)"))
      ;; Replaced definitions.
      (list "a replaced template scale's bad-form is still an error"
            (at 'bad-form tshape 1)
            (string-in dir "(piece \"P\")" "(use \"tshape.nts\")" "(scale s a)"))
      (list "a duplicate in a template is an error even if the piece replaces the name"
            (at 'duplicate-definition dup 2)
            (string-in dir "(piece \"P\")" "(use \"dup.nts\")" "(scale s c)"))
      (list "a replaced template scale's bad-degree is not checked"
            'no-error
            (string-in dir "(piece \"P\")" "(use \"tdeg.nts\")" "(scale s a)"))
      (list "a replaced template instrument's unknown-note is not checked"
            'no-error
            (string-in dir "(piece \"P\")" "(use \"tnote.nts\")"
                       "(instrument tx ts a1)"))))
    (test-equal "read-error in the piece before a template error" 'read-error
      (kind-of (catch-syntax-error
                (string-in dir "(piece \"P\")" "(use \"bf.nts\")" "(scale s a"))))))

;;; ------------------------------------------------------------------
;;; examples/tenzer1.nts reads end to end (slice 4)

(test-group "tenzer1"
  (let ((pc (read-file "examples/tenzer1.nts")))
    (test-assert "reads into a piece" (piece? pc))
    (test-equal "title" "Eight-pulse gong cycle" (piece-title pc))
    (test-equal "steps-per-pulse" 1 (piece-steps-per-pulse pc))
    (test-equal "steps-per-system" #f (piece-steps-per-system pc))
    (test-equal "length" 9 (piece-length pc))
    (test-equal "scales: selisir, then gong-kebyar's stroke sets"
      '(selisir kempli-strokes gong-strokes kendang-strokes)
      (scale-names pc))
    (test-equal "instruments, including those no part plays"
      '(ugal reyong kempli gong kendang)
      (instrument-names pc))
    (test-equal "parts" '(ugal kempli gong) (map part-name (piece-parts pc)))
    (test-equal "groups" '("Ugal" "Kempli" "Gong & kempur")
      (map group-label (piece-groups pc)))
    (test-equal "ugal events"
      '((0 1 (3)) (1 1 (5)) (2 1 (4)) (3 1 (6)) (4 1 (5))
        (5 1 (3)) (6 1 (5)) (7 1 (4)) (8 1 (3)))
      (part-triples pc 'ugal))
    (test-equal "kempli events"
      (map (lambda (i) (list i 1 '(0))) (iota 9))
      (part-triples pc 'kempli))
    (test-equal "gong events"
      '((0 1 (0)) (4 1 (0)) (5 1 (1)) (7 1 (1)) (8 1 (0)))
      (part-triples pc 'gong))
    (test-equal "selisir shows its degrees by vowel"
      '("i" "o" "e" "u" "a")
      (map degree-display (scale-degrees (scale-named pc 'selisir))))
    (test-equal "ugal lane labels are vowel and octave"
      '("o1" "i3")
      (let* ((inst (instrument-named pc 'ugal))
             (v (instrument-notes inst)))
        (list (note-label inst (vector-ref v 0))
              (note-label inst (vector-ref v 9)))))
    (test-equal "selisir's file and line"
      '("selisir.nts" 5)
      (let ((loc (scale-location (scale-named pc 'selisir))))
        (list (basename (source-location-file loc)) (source-location-line loc))))
    (test-equal "ugal instrument's file and line"
      '("gong-kebyar.nts" 14)
      (let ((loc (instrument-location (instrument-named pc 'ugal))))
        (list (basename (source-location-file loc)) (source-location-line loc))))
    (test-equal "parts' files are tenzer1.nts, with their lines"
      '(("tenzer1.nts" 18) ("tenzer1.nts" 19) ("tenzer1.nts" 20))
      (map (lambda (p)
             (let ((loc (part-location p)))
               (list (basename (source-location-file loc))
                     (source-location-line loc))))
           (piece-parts pc)))
    (test-equal "groups' lines" '(22 23 24)
      (map group-line (piece-groups pc)))))

(define runner (test-runner-current))
(test-end "reader")

(remove-temp-files)
(remove-tpl-root)

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
