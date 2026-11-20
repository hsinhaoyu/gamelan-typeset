;;; Unit tests for (notasi typst): writing the figure file.
;;;
;;; Written from doc/design/05-typst-backend.md ("Writing the figure
;;; file"), not from the implementation.  The rest of (notasi typst)
;;; is milestone 4.
;;;
;;; Choices where the spec leaves room (also noted at the tests):
;;; - Most tests use small hand-made figures (any value write-json
;;;   accepts), so that the expected text is easy to state; one test
;;;   uses a real figure from layout-piece.
;;; - "In UTF-8" is checked at the byte level, so the file must be
;;;   UTF-8 whatever the locale's default port encoding is.
;;; - Each write-figure call happens inside a test, so a failing or
;;;   missing write-figure fails tests rather than stopping the file.

(use-modules (srfi srfi-64)
             (ice-9 binary-ports)
             (ice-9 exceptions)
             (ice-9 ftw)
             (ice-9 match)
             (ice-9 textual-ports)
             (rnrs bytevectors)
             (notasi json)
             (notasi layout)
             (notasi reader)
             (notasi typst))

;;; ------------------------------------------------------------------
;;; Helpers

(define tmp-dir
  (mkdtemp (string-append (or (getenv "TMPDIR") "/tmp") "/notasi-XXXXXX")))

(define (tmp-path name)
  (string-append tmp-dir "/" name))

(define (read-text path)
  (call-with-input-file path get-string-all #:encoding "UTF-8"))

(define (read-bytes path)
  (call-with-input-file path get-bytevector-all #:binary #t))

(define (write-text path text)
  (call-with-output-file path (lambda (port) (put-string port text))
    #:encoding "UTF-8"))

(define (expected-text figure)
  "What write-figure should write for FIGURE: pretty JSON and a newline."
  (string-append (json-string figure) "\n"))

(define (raises-error-about? bad thunk)
  "#t if THUNK raises an &error whose irritants include BAD (the value the
JSON writer can't write), #f if it returns or raises anything else.  An
unbound write-figure is an &error too, so checking the irritant keeps
these tests from passing by accident."
  (guard (e ((and (error? e)
                  (exception-with-irritants? e)
                  (member bad (exception-irritants e)))
             #t)
            (#t #f))
    (thunk)
    #f))

(define (cleanup)
  "Delete tmp-dir and every file in it."
  (for-each (lambda (name) (delete-file (tmp-path name)))
            (scandir tmp-dir (lambda (f) (not (member f '("." ".."))))))
  (rmdir tmp-dir))

;;; A small figure with nested values and non-ASCII text.
(define small-figure
  `((title . "Tabuh · Pelegongan é")
    (systems . #(((label . "Gangsa") (lanes . #("dong" "dèng")))))
    (count . 3)
    (ready . #t)
    (subtitle . null)))

;;; Figures write-json can't write, by a short name used in file names.
(define bad-figures
  ;; (NAME BAD-VALUE FIGURE)
  `(("rational" 1/2 ((title . "x") (width . 1/2)))
    ("symbol" bold ((title . "x") (look . bold)))))

(test-begin "typst")

;;; ------------------------------------------------------------------
;;; Writing

(let ((path (tmp-path "small.json")))
  (test-equal "writes the figure as pretty JSON ending with a newline"
    (expected-text small-figure)
    (begin (write-figure small-figure path)
           (read-text path)))
  (test-equal "writes the file in UTF-8 (bytes)"
    (string->utf8 (expected-text small-figure))
    (read-bytes path)))

(let ((path (tmp-path "replace.json")))
  ;; The old contents are longer, so a write that doesn't truncate
  ;; would leave a tail behind.
  (write-text path (string-append "{\"old\": \"" (make-string 200 #\x) "\"}\n"))
  (test-equal "replaces an existing file's contents"
    (expected-text '((a . 1)))
    (begin (write-figure '((a . 1)) path)
           (read-text path))))

;;; ------------------------------------------------------------------
;;; A figure that can't be written

(for-each
 (match-lambda
   ((name bad figure)
    (let ((path (tmp-path (string-append "bad-new-" name ".json"))))
      (test-assert (string-append "can't be written (" name "): raises an &error")
        (raises-error-about? bad (lambda () (write-figure figure path))))
      (test-assert (string-append "can't be written (" name "): leaves no file")
        (not (file-exists? path))))
    (let ((path (tmp-path (string-append "bad-old-" name ".json")))
          (old "{\n  \"old\": true\n}\n"))
      (write-text path old)
      (test-assert (string-append "can't be written (" name "), file there: raises an &error")
        (raises-error-about? bad (lambda () (write-figure figure path))))
      (test-equal (string-append "can't be written (" name "): leaves an existing file as it was")
        old
        (read-text path)))))
 bad-figures)

;;; ------------------------------------------------------------------
;;; A real figure

(let ((figure (layout-piece (read-piece-file "examples/tenzer1.gml")))
      (path (tmp-path "tenzer1.json")))
  (test-equal "writes a real figure (examples/tenzer1.gml)"
    (string->utf8 (expected-text figure))
    (begin (write-figure figure path)
           (read-bytes path))))

(cleanup)

(define runner (test-runner-current))
(test-end "typst")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
