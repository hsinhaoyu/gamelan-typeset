;;; Guards against README.md drifting from the code.
;;; - Every module file in gamelan/ must be mentioned in README.md.
;;; - Every gamelan/*.scm path README.md mentions must exist.
;;; - Every `make <target>` README.md mentions must be a Makefile target.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 ftw)
             (ice-9 regex)
             (ice-9 textual-ports))

(define (slurp file)
  (call-with-input-file file get-string-all))

(define (matches pattern text group)
  "Return the GROUPth submatch of every match of PATTERN in TEXT."
  (map (lambda (m) (match:substring m group))
       (list-matches pattern text)))

(define readme (slurp "README.md"))
(define makefile (slurp "Makefile"))

(define module-files
  (map (lambda (f) (string-append "gamelan/" f))
       (scandir "gamelan" (lambda (f) (string-suffix? ".scm" f)))))

(define readme-modules
  (delete-duplicates (matches "gamelan/[a-z0-9-]+\\.scm" readme 0)))

(define readme-targets
  (delete-duplicates (matches "make ([a-z0-9-]+)" readme 1)))

(test-begin "readme")

(for-each
 (lambda (f)
   (test-assert (string-append "README mentions " f)
     (string-contains readme f)))
 module-files)

(for-each
 (lambda (f)
   (test-assert (string-append "README path exists: " f)
     (file-exists? f)))
 readme-modules)

(for-each
 (lambda (t)
   (test-assert (string-append "Makefile has target: " t)
     (string-match (string-append "(^|\n)" t ":") makefile)))
 readme-targets)

(define runner (test-runner-current))
(test-end "readme")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
