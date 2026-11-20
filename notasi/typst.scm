;;; (notasi typst) -- The Guile side of the Typst backend.  See
;;; doc/design/05-typst-backend.md.
;;;
;;; Implemented: writing a figure as a JSON file.  The entry file and
;;; running Typst are milestone 4.

(define-module (notasi typst)
  #:use-module (notasi json)
  #:export (write-figure))

(define (write-figure figure path)
  "Write FIGURE (from `layout-piece') to the file PATH as pretty JSON in
UTF-8, ending with a newline, replacing any file already there.  The
JSON is built first, so a figure that can't be written raises an &error
and leaves PATH as it was."
  (let ((text (json-string figure)))
    (call-with-output-file path
      (lambda (port)
        (display text port)
        (newline port))
      #:encoding "UTF-8")))
