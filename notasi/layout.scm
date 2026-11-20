;;; (notasi layout) -- Lay out a piece as a figure: systems, groups,
;;; lanes and events, each event with its look.  See
;;; doc/design/04-layout.md.
;;;
;;; The figure is the JSON value of 05's contract itself: alists with
;;; symbol keys for objects, vectors for arrays, the symbol `null' for
;;; null.  `write-json' from (notasi json) writes it as it is.

(define-module (notasi layout)
  #:use-module (notasi piece)
  #:use-module (notasi style)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (layout-piece))

(define (null-if-false x)
  (or x 'null))

;;; ------------------------------------------------------------------
;;; Lanes

(define (lane-owners group)
  "The lanes of GROUP, top first, as (INSTRUMENT . NOTE) pairs."
  (let ((instruments (delete-duplicates (map part-instrument (group-parts group))
                                        eq?)))
    (map (lambda (note)
           (cons (find (lambda (instrument)
                         (vector-index (lambda (n) (eq? n note))
                                       (instrument-notes instrument)))
                       instruments)
                 note))
         (group-lanes group))))

(define (vector-index pred vector)
  (let loop ((i 0))
    (cond ((= i (vector-length vector)) #f)
          ((pred (vector-ref vector i)) i)
          (else (loop (1+ i))))))

(define (lane-label lane)
  (match lane
    ((instrument . note) (note-label instrument note))))

;;; ------------------------------------------------------------------
;;; Events

(define (note-events part lanes style)
  "PART's events, one per note (a chord gives several), as
(START DURATION LANE LOOK) lists.  The look's text is dropped (#f) when
the instrument doesn't show names (ADR 0019)."
  (let* ((instrument (part-instrument part))
         (names? (instrument-show-names? instrument)))
    (append-map
     (lambda (event)
       (map (lambda (index)
              (let ((note (vector-ref (instrument-notes instrument) index)))
                (list (event-start event)
                      (event-duration event)
                      (list-index (match-lambda ((_ . n) (eq? n note))) lanes)
                      (let ((look (note-look style instrument note)))
                        (if names?
                            look
                            (make-look (look-fill look) #f
                                       (look-text-color look)))))))
            (event-notes event)))
     (part-events part))))

(define (clip-event event from to)
  "EVENT cut to the steps [FROM, TO), as a JSON event object with a
start relative to FROM, or #f if it doesn't sound there."
  (match event
    ((start duration lane look)
     (let ((end (+ start duration)))
       (and (< start to) (> end from)
            (let ((first (max start from)))
              `((start . ,(- first from))
                (dur . ,(- (min end to) first))
                (lane . ,lane)
                (text . ,(null-if-false (look-text look)))
                (fill . ,(null-if-false (look-fill look)))
                (text_color . ,(look-text-color look))
                (continued . ,(< start from)))))))))

(define (event<? a b)
  (match (list a b)
    (((start-a _ lane-a _) (start-b _ lane-b _))
     (or (< start-a start-b)
         (and (= start-a start-b) (< lane-a lane-b))))))

;;; ------------------------------------------------------------------
;;; Groups and systems

;;; A group prepared once for the whole piece: its JSON label fields,
;;; its lanes, and each voice's events in the whole piece.
(define (prepare-group group style)
  (let ((lanes (lane-owners group)))
    (list group
          lanes
          (map (lambda (part)
                 (cons (symbol->string (part-name part))
                       (sort (note-events part lanes style) event<?)))
               (group-parts group)))))

(define (group-in-system prepared from to)
  (match prepared
    ((group lanes voices)
     `((label . ,(group-label group))
       (subtitle . ,(null-if-false (group-subtitle group)))
       (lanes . ,(list->vector (map lane-label lanes)))
       (voices
        . ,(list->vector
            (map (match-lambda
                   ((name . events)
                    `((name . ,name)
                      (events
                       . ,(list->vector
                           (filter-map (lambda (e) (clip-event e from to))
                                       events))))))
                 voices)))))))

(define (system-starts length steps)
  (iota (ceiling-quotient length steps) 0 steps))

(define (ceiling-quotient n d)
  (quotient (+ n d -1) d))

(define (systems piece prepared)
  (let* ((length (piece-length piece))
         (steps (or (piece-steps-per-system piece) length)))
    (if (zero? length)
        #()
        (list->vector
         (map (lambda (start)
                (let ((end (min length (+ start steps))))
                  `((start . ,start)
                    (steps . ,(- end start))
                    (groups . ,(list->vector
                                (map (lambda (g) (group-in-system g start end))
                                     prepared))))))
              (system-starts length steps))))))

;;; ------------------------------------------------------------------
;;; Sizes

(define (em x)
  "X (exact) as a length in em with one decimal, ties rounded up."
  (let ((tenths (floor (+ (* x 10) 1/2))))
    (string-append (number->string (quotient tenths 10)) "."
                   (number->string (remainder tenths 10)) "em")))

(define (longest strings)
  (fold (lambda (s m) (max m (string-length s))) 0 strings))

(define (sizes prepared)
  (let ((labels (append-map (match-lambda
                              ((group _ _)
                               (filter string? (list (group-label group)
                                                     (group-subtitle group)))))
                            prepared))
        (lane-labels (append-map (match-lambda
                                   ((_ lanes _) (map lane-label lanes)))
                                 prepared)))
    `((label_width . ,(em (+ (* 3/5 (longest labels)) 3/2)))
      (lane_width . ,(em (+ (* 13/25 (longest lane-labels)) 1)))
      (step_width . "2.0em")
      (row_height . "2.0em"))))

;;; ------------------------------------------------------------------
;;; Entry point

(define* (layout-piece piece #:key (style (default-style)))
  "Lay out PIECE as a figure: the JSON value of the contract in
doc/design/05-typst-backend.md, with each note drawn as STYLE says."
  (let ((prepared (map (lambda (group) (prepare-group group style))
                       (piece-groups piece))))
    `((version . 1)
      (title . ,(piece-title piece))
      (steps_per_pulse . ,(piece-steps-per-pulse piece))
      (sizes . ,(sizes prepared))
      (systems . ,(systems piece prepared))
      (caption . null))))
