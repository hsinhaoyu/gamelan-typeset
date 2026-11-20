;;; Unit tests for (notasi reader), slice 1 (feat/reader-forms):
;;; the public interface, the &notasi-syntax-error condition, reading
;;; forms, dispatch, and the `piece` form with its options.
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
         (list "scale" "(scale selisir (ding (alias i)) dong deng dung dang)")
         (list "strokes" "(strokes gong-strokes G P)")
         (list "instrument" "(instrument gong gong-strokes G)")
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

(define runner (test-runner-current))
(test-end "reader")

(remove-temp-files)

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
