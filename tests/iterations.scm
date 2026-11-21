;;; Checks the iterations in doc/iterations/ (ADR 0023).
;;; - Every iteration folder is named NN-kebab-name.
;;; - Iteration numbers run 1..n with no gaps or duplicates.
;;; - Each iteration has a README.md with a Status: line of deciding,
;;;   building or done.
;;; - At most one iteration is building.
;;;
;;; /start-milestone and /promote-design read the Status: line.  This
;;; file is dev-only, like the folder it checks (see the release skill).

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 ftw)
             (ice-9 match)
             (ice-9 regex)
             (ice-9 textual-ports))

(define dir "doc/iterations")

(define (slurp file)
  (call-with-input-file file get-string-all))

(define (path . parts)
  (string-join (cons dir parts) "/"))

(define folders
  (scandir dir (lambda (f)
                 (and (not (member f '("." "..")))
                      (file-is-directory? (path f))))))

(define name-rx (make-regexp "^([0-9]{2})-[a-z0-9]+(-[a-z0-9]+)*$"))

(define status-rx
  (make-regexp "^Status: (deciding|building|done)$" regexp/newline))

(define (iteration-number folder)
  "Return the number at the start of FOLDER's name, or #f if it is malformed."
  (match (regexp-exec name-rx folder)
    (#f #f)
    (m (string->number (match:substring m 1)))))

(define (status folder)
  "Return FOLDER's status as a string, or #f if it has no valid one."
  (let ((readme (path folder "README.md")))
    (and (file-exists? readme)
         (match (regexp-exec status-rx (slurp readme))
           (#f #f)
           (m (match:substring m 1))))))

(test-begin "iterations")

(test-assert "doc/iterations has at least one iteration"
  (pair? folders))

(test-assert "doc/iterations has backlog.md"
  (file-exists? (path "backlog.md")))

(for-each
 (lambda (f)
   (test-assert (string-append "folder is named NN-kebab-name: " f)
     (iteration-number f))
   (test-assert (string-append "has a README.md: " f)
     (file-exists? (path f "README.md")))
   (test-assert (string-append "valid Status: line (deciding, building, done): " f)
     (status f)))
 folders)

(test-equal "iteration numbers run 1..n with no gaps or duplicates"
  (iota (length folders) 1)
  (sort (filter-map iteration-number folders) <))

(test-assert "at most one iteration is building"
  (<= (count (lambda (f) (equal? (status f) "building")) folders) 1))

(define runner (test-runner-current))
(test-end "iterations")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
