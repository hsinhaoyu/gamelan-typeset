;;; Template tests: typst/notasi.typ draws every golden figure.
;;; See doc/design/05-typst-backend.md, "Typst template design"
;;; ("Tests (slice 1)") and "Version pinning".
;;; - Each tests/golden/NAME.json is compiled with `score`, from an
;;;   entry file written in a fresh temporary folder next to copies of
;;;   the template and the JSON.  `typst compile` must succeed, write a
;;;   non-empty PDF, and print no warning.
;;; - A few small figures written here by hand cover cases the golden
;;;   files may not: no systems at all (empty content), and a system
;;;   that doesn't start on a pulse.
;;; - If `typst` isn't installed, one test says so and fails (CI always
;;;   installs it, 0.15.1); no compile is tried.
;;;
;;; Run from the repo root: guile -L . tests/template.scm

(use-modules (srfi srfi-1)
             (srfi srfi-9)
             (srfi srfi-64)
             (ice-9 ftw)
             (ice-9 textual-ports))

(define template-path "typst/notasi.typ")
(define golden-dir "tests/golden")

(define (read-text path)
  (call-with-input-file path get-string-all #:encoding "UTF-8"))

(define (write-text path text)
  (call-with-output-file path (lambda (port) (put-string port text))
    #:encoding "UTF-8"))

(define (golden-names)
  "The names of the golden figures, without \".json\", sorted."
  (map (lambda (f) (string-drop-right f 5))
       (or (scandir golden-dir (lambda (f) (string-suffix? ".json" f)))
           '())))

(define (typst-installed?)
  (zero? (status:exit-val
          (system* "sh" "-c" "command -v typst >/dev/null 2>&1"))))

(define (entry-text json-name)
  "The entry file that draws the figure in JSON-NAME with `score`."
  (string-append
   "#import \"notasi.typ\": score\n"
   "#set page(width: auto, height: auto, margin: 14pt)\n"
   "#score(json(\"" json-name "\"))\n"))

(define (remove-folder dir)
  "Delete DIR and the files in it (it has no subfolders)."
  (for-each (lambda (f) (delete-file (string-append dir "/" f)))
            (scandir dir (lambda (f) (not (member f '("." ".."))))))
  (rmdir dir))

(define-record-type <outcome>
  (make-outcome status pdf-size output)
  outcome?
  (status outcome-status)        ; typst's exit status
  (pdf-size outcome-pdf-size)    ; size of out.pdf in bytes, 0 if none
  (output outcome-output))       ; what typst printed (stdout + stderr)

(define (compile-figure json-name json-text)
  "Compile JSON-TEXT, saved as JSON-NAME, with the template in a fresh
temporary folder, and return the outcome.  A missing template is not
copied, so typst itself reports it."
  (let ((dir (mkdtemp (string-append (or (getenv "TMPDIR") "/tmp")
                                     "/notasi-template-XXXXXX"))))
    (dynamic-wind
      (const #f)
      (lambda ()
        (when (file-exists? template-path)
          (copy-file template-path (string-append dir "/notasi.typ")))
        (write-text (string-append dir "/" json-name) json-text)
        (write-text (string-append dir "/entry.typ") (entry-text json-name))
        (let* ((status (status:exit-val
                        (system* "sh" "-c"
                                 "cd \"$1\" && typst compile entry.typ out.pdf >log.txt 2>&1"
                                 "sh" dir)))
               (pdf (string-append dir "/out.pdf"))
               (log (string-append dir "/log.txt")))
          (make-outcome status
                        (if (file-exists? pdf) (stat:size (stat pdf)) 0)
                        (if (file-exists? log) (read-text log) ""))))
      (lambda () (remove-folder dir)))))

(define (warning-lines output)
  "The lines of OUTPUT where typst reports a warning."
  (filter (lambda (line) (string-prefix? "warning" line))
          (string-split output #\newline)))

(define (check-figure label json-name json-text)
  "Two tests for one figure: it compiles to a non-empty PDF, and typst
prints no warning.  Typst's output is shown when either fails."
  (let ((outcome (compile-figure json-name json-text)))
    (unless (and (eqv? 0 (outcome-status outcome))
                 (positive? (outcome-pdf-size outcome))
                 (null? (warning-lines (outcome-output outcome))))
      (format (current-error-port) "typst output for ~a:~%~a~%"
              label (outcome-output outcome)))
    (test-assert (string-append label ": typst compile succeeds")
      (eqv? 0 (outcome-status outcome)))
    (test-assert (string-append label ": out.pdf is not empty")
      (positive? (outcome-pdf-size outcome)))
    (test-equal (string-append label ": typst prints no warning")
      '()
      (warning-lines (outcome-output outcome)))))

;;; Hand-written figures, following 05's contract (key order from 04,
;;; "Public interface").

(define no-systems
  "{
  \"version\": 1,
  \"title\": \"Nothing\",
  \"steps_per_pulse\": 4,
  \"sizes\": {
    \"label_width\": \"5em\",
    \"lane_width\": \"2em\",
    \"step_width\": \"2.6em\",
    \"row_height\": \"1.5em\"
  },
  \"systems\": [],
  \"caption\": null
}
")

;; A system starting mid-pulse (start 2, steps_per_pulse 4), with a
;; continued note, a note drawn as text only, a null subtitle, and a
;; group with no events.
(define off-pulse
  "{
  \"version\": 1,
  \"title\": \"Off pulse\",
  \"steps_per_pulse\": 4,
  \"sizes\": {
    \"label_width\": \"6em\",
    \"lane_width\": \"2.5em\",
    \"step_width\": \"2.6em\",
    \"row_height\": \"1.5em\"
  },
  \"systems\": [
    {
      \"start\": 2,
      \"steps\": 6,
      \"groups\": [
        {
          \"label\": \"Reyong\",
          \"subtitle\": null,
          \"lanes\": [\"nong1\", \"nang1\"],
          \"voices\": [
            {
              \"name\": \"polos\",
              \"events\": [
                {
                  \"start\": 0,
                  \"dur\": 2,
                  \"lane\": 1,
                  \"text\": \"nang\",
                  \"fill\": \"#1b9e77\",
                  \"text_color\": \"#ffffff\",
                  \"continued\": true
                },
                {
                  \"start\": 3,
                  \"dur\": 1,
                  \"lane\": 0,
                  \"text\": \"x\",
                  \"fill\": null,
                  \"text_color\": \"#222222\",
                  \"continued\": false
                }
              ]
            }
          ]
        },
        {
          \"label\": \"Kendang\",
          \"subtitle\": \"wadon\",
          \"lanes\": [\"dag\"],
          \"voices\": [
            {
              \"name\": \"wadon\",
              \"events\": []
            }
          ]
        }
      ]
    }
  ],
  \"caption\": null
}
")

;;; The tests.

(test-begin "template")

(define names (golden-names))

(test-assert "there is at least one golden figure in tests/golden/"
  (pair? names))

(if (typst-installed?)
    (begin
      (for-each
       (lambda (name)
         (let ((file (string-append name ".json")))
           (check-figure (string-append golden-dir "/" file) file
                         (read-text (string-append golden-dir "/" file)))))
       names)
      (check-figure "a figure with no systems" "empty.json" no-systems)
      (check-figure "a system starting mid-pulse" "off-pulse.json"
                    off-pulse))
    (test-assert "typst is installed (CI installs 0.15.1)" #f))

(define runner (test-runner-current))
(test-end "template")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
