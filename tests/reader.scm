;;; Unit tests for (notasi reader), slices 1 and 2.
;;; Slice 1 (feat/reader-forms): the public interface, the
;;; &notasi-syntax-error condition, reading forms, dispatch, and the
;;; `piece` form with its options.
;;; Slice 2 (feat/reader-scales): the `scale`, `strokes` and
;;; `instrument` forms in a single file, their records, their error
;;; cases and the order in which the checks run.
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
  (let* ((path (write-temp-file "ok.gml"
                                (lines ";; a piece" "(piece \"From a file\" (steps-per-system 12))" "")))
         (pc (read-piece-file path)))
    (test-equal "title" "From a file" (piece-title pc))
    (test-equal "steps-per-system" 12 (piece-steps-per-system pc))
    (test-equal "default steps-per-pulse" 4 (piece-steps-per-pulse pc))
    (test-equal "length 0" 0 (piece-length pc)))

  (let* ((path (write-temp-file "dup.gml"
                                (lines "(piece \"A\")" ";; again" "(piece \"B\")")))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "error kind" 'duplicate-piece (kind-of c))
    (test-equal "error file is the path given" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "error line" 3
      (and (notasi-syntax-error? c) (notasi-syntax-error-line c))))

  (let* ((path (write-temp-file "missing.gml" ";; nothing here\n"))
         (c (catch-syntax-error (lambda () (read-piece-file path)))))
    (test-equal "missing-piece kind" 'missing-piece (kind-of c))
    (test-equal "missing-piece file is the path given" path
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "missing-piece line is #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-line c))))

  (let* ((path (write-temp-file "unbalanced.gml"
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
   (list (list "use" "(use gong-kebyar)")
         (list "use with a string" "(use \"gong-kebyar.gml\")")
         (list "part" "(part gong gong G - - - G P - P)")
         (list "group" "(group \"Reyong\" polos sangsih)")
         (list "text" "(text \"A note\")")))
  (test-equal "line 2" '(not-implemented 2)
    (string-error (lines "(piece \"P\")" "(part a b 1 2)")))
  (test-equal "first not-implemented form in file order" '(not-implemented 4)
    (string-error (lines "(piece \"P\")" "" "" "(group \"G\" a)" "(text \"x\")")))
  (let ((c (catch-syntax-error
            (lambda () (read-piece-string (lines "(piece \"P\")" "(part a b 1 2)"))))))
    (test-equal "not-implemented: file #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-file c)))
    (test-equal "not-implemented: part field #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-part c)))
    (test-equal "not-implemented: step field #f" #f
      (and (notasi-syntax-error? c) (notasi-syntax-error-step c))))
  (let* ((path (write-temp-file "text.gml" (lines "(piece \"P\")" "(text \"x\")")))
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
                             "(instrument ugal selisir a1 i2)"
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
  (let* ((path (write-temp-file "defs.gml" defs-text))
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

;;; The contents of templates/selisir.gml and templates/gong-kebyar.gml
;;; (without its `use`), pasted into one file.
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
      (let* ((path (write-temp-file (string-append name ".gml") contents))
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
    (list "use comes before undefined-scale" '(not-implemented 2)
          (lines "(piece \"P\")" "(use gong-kebyar)"
                 "(instrument ugal selisir ding1)"))
    (list "use comes before bad-form" '(not-implemented 2)
          (lines "(piece \"P\")" "(use gong-kebyar)" "(scale)"))
    (list "use with a string comes before unknown-note" '(not-implemented 2)
          (lines "(piece \"P\")" "(use \"defs.gml\")" "(scale s ding)"
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
    (list "unknown-note comes before part's not-implemented" '(unknown-note 4)
          (lines "(piece \"P\")" "(part p x 1)" "(scale s ding)"
                 "(instrument x s foo1)"))
    (list "undefined-scale comes before group's not-implemented"
          '(undefined-scale 3)
          (lines "(piece \"P\")" "(group \"G\" p)" "(instrument x s ding1)"))
    (list "bad-form comes before text's not-implemented" '(bad-form 3)
          (lines "(piece \"P\")" "(text \"x\")" "(scale s)"))
    (list "duplicate-note comes before part's not-implemented"
          '(duplicate-note 4)
          (lines "(piece \"P\")" "(strokes g G)" "(part p x 1)"
                 "(instrument x g G G)"))
    (list "valid definitions, then a part: not-implemented at the part"
          '(not-implemented 4)
          (lines "(piece \"P\")" "(strokes g G)" "(instrument x g G)"
                 "(part p x G)"))
    (list "valid definitions after a text: not-implemented at the text"
          '(not-implemented 2)
          (lines "(piece \"P\")" "(text \"x\")" "(strokes g G)"
                 "(instrument x g G)")))))

(define runner (test-runner-current))
(test-end "reader")

(remove-temp-files)

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
