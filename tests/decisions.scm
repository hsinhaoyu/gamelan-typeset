;;; Checks the decision log in doc/decisions/.
;;; - Every ADR file is named NNNN-kebab-title.md.
;;; - ADR numbers run 1..n with no gaps or duplicates.
;;; - Each ADR's "# NNNN" heading matches its filename.
;;; - Each ADR has a valid Status: line.
;;; - "superseded by NNNN" points to an existing ADR.
;;; - Every ADR is listed in doc/decisions/README.md.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 ftw)
             (ice-9 match)
             (ice-9 regex)
             (ice-9 textual-ports))

(define dir "doc/decisions")

(define (slurp file)
  (call-with-input-file file get-string-all))

(define (path file)
  (string-append dir "/" file))

(define index (slurp (path "README.md")))

(define adr-files
  (scandir dir (lambda (f)
                 (and (string-suffix? ".md" f)
                      (not (string=? f "README.md"))))))

(define name-rx (make-regexp "^([0-9]{4})-[a-z0-9]+(-[a-z0-9]+)*\\.md$"))

(define status-rx
  (make-regexp
   "^Status: (proposed|accepted \\([0-9]{4}-[0-9]{2}-[0-9]{2}\\)|superseded by ([0-9]{4})|deprecated)$"
   regexp/newline))

(define (adr-number file)
  "Return the number at the start of FILE's name, or #f if it is malformed."
  (match (regexp-exec name-rx file)
    (#f #f)
    (m (string->number (match:substring m 1)))))

(define (file-for-number n)
  (find (lambda (f) (eqv? (adr-number f) n)) adr-files))

(test-begin "decisions")

(test-assert "doc/decisions has at least one ADR"
  (pair? adr-files))

(for-each
 (lambda (f)
   (test-assert (string-append "ADR filename is NNNN-kebab-title.md: " f)
     (adr-number f)))
 adr-files)

(test-equal "ADR numbers run 1..n with no gaps or duplicates"
  (iota (length adr-files) 1)
  (sort (filter-map adr-number adr-files) <))

(for-each
 (lambda (f)
   (let ((text (slurp (path f)))
         (n (adr-number f)))
     (when n
       (test-assert (string-append "heading matches filename: " f)
         (string-prefix? (string-append "# " (substring f 0 4) " ") text)))
     (let ((status (regexp-exec status-rx text)))
       (test-assert (string-append "valid Status: line: " f)
         status)
       (match (and status (match:substring status 2))
         (#f #t)
         (target
          (test-assert (string-append "superseding ADR " target " exists: " f)
            (file-for-number (string->number target))))))
     (test-assert (string-append "listed in README index: " f)
       (string-contains index (string-append "(" f ")")))))
 adr-files)

(define runner (test-runner-current))
(test-end "decisions")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
