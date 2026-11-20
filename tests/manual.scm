;;; Keeps the user manual's examples honest.  See doc/manual/STYLE.md.
;;; - Every example in doc/manual/src/examples/ reads without errors.
;;; - Every {{#include ...}} in a manual page points to a file that exists.
;;; - Every example is included by at least one page.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 ftw)
             (ice-9 regex)
             (ice-9 textual-ports)
             (notasi piece)
             (notasi reader))

(define src "doc/manual/src")
(define examples-dir (string-append src "/examples"))

(define (slurp file)
  (call-with-input-file file get-string-all))

(define (files-under dir suffix)
  "Return every file below DIR whose name ends in SUFFIX, as paths."
  (let walk ((dir dir))
    (append-map
     (lambda (name)
       (let ((path (string-append dir "/" name)))
         (cond ((eq? 'directory (stat:type (stat path))) (walk path))
               ((string-suffix? suffix name) (list path))
               (else '()))))
     (or (scandir dir (lambda (f) (not (member f '("." ".."))))) '()))))

(define (canonical path)
  "Resolve . and .. in PATH without touching the file system."
  (string-join
   (reverse
    (fold (lambda (part acc)
            (cond ((member part '("" ".")) acc)
                  ((string=? part "..") (if (null? acc) acc (cdr acc)))
                  (else (cons part acc))))
          '()
          (string-split path #\/)))
   "/"))

(define (includes page)
  "Return the files PAGE includes, as paths relative to the repo root."
  (map (lambda (m)
         (canonical (string-append (dirname page) "/" (match:substring m 1))))
       (list-matches "\\{\\{#include ([^}:[:space:]]+)" (slurp page))))

(define examples (files-under examples-dir ".gml"))
(define pages (files-under src ".md"))
(define included (append-map includes pages))

(test-begin "manual")

(for-each
 (lambda (f)
   (test-assert (string-append "example reads: " f)
     (piece? (read-piece-file f))))
 examples)

(for-each
 (lambda (page)
   (for-each
    (lambda (f)
      (test-assert (string-append page " includes a file that exists: " f)
        (file-exists? f)))
    (includes page)))
 pages)

(for-each
 (lambda (f)
   (test-assert (string-append "example is used by a page: " f)
     (member f included)))
 examples)

(define runner (test-runner-current))
(test-end "manual")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
