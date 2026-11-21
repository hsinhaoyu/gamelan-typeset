;;; Unit tests for (notasi layout): layout-piece → figure.
;;;
;;; Written from doc/design/04-layout.md ("Public interface", "Systems",
;;; "Groups and lanes", "Lane labels", "Sizes", "Note style") and
;;; doc/design/05-typst-backend.md ("JSON contract (version 1)", "JSON
;;; writing"), with ADRs 0002, 0005, 0006, 0009 and 0017, not from the
;;; implementation.
;;;
;;; The figure is the JSON value itself: alists with symbol keys in the
;;; documented order, vectors for arrays, the symbol `null` for null.
;;; Every call to layout-piece happens inside a test, so a failing or
;;; missing layout-piece fails tests instead of stopping the file.
;;;
;;; Choices made where the doc is not explicit:
;;; - Sizes count characters (string-length), not bytes: "Kempli · Gong"
;;;   is 13 characters → 0.6 × 13 + 1.5 = "9.3em".
;;; - Lengths always carry one decimal, also for whole numbers: a lane
;;;   label of 2 characters gives 0.52 × 2 + 1 = 2.04 → "2.0em".
;;; - A group whose parts are all rests has lanes #() and adds 0 to the
;;;   longest lane label; its voices still appear, with events #().
;;; - A piece of length 0 has systems #(); its sizes are not tested when
;;;   it has groups (the doc says sizes are "for the whole figure (all
;;;   systems)", which is unclear when there are no systems).  With no
;;;   groups at all: "1.5em" and "1.0em".
;;; - steps-per-system larger than the piece gives one system whose
;;;   `steps` is the piece length ("the last system may be shorter").
;;; - A note cut at a boundary keeps its own lane, text and look in
;;;   every piece; only start, dur and continued change.
;;; - An event that ends exactly on a boundary, or starts on one, is not
;;;   cut: one piece, continued #f.
;;; - A chord crossing a boundary is cut note by note: each of its
;;;   events is cut like a single note.
;;; - A custom scheme's look is used as it is (04, "Note style"); a fill
;;;   of #f from it also becomes null.
;;;
;;; Slice feat/music-syntax (03, "Slices (iteration 2)"): no note shows
;;; its name, so every event's `text` is null, and a piece read from
;;; text has every part in its own default group (label = part name,
;;; subtitle null), because top-level `group` forms are gone.  Layout
;;; still draws whatever groups the piece has, so tests of written
;;; groups (subtitles, several voices, merged lanes) build those groups
;;; by hand with `regroup`.

(use-modules (srfi srfi-1)
             (srfi srfi-64)
             (ice-9 match)
             (notasi piece)
             (notasi reader)
             (notasi style)
             (notasi json)
             (notasi layout))

;;; ------------------------------------------------------------------
;;; Helpers

(define (field obj key)
  "The value of KEY in the JSON object OBJ (an alist); an error if absent."
  (match (assq key obj)
    ((_ . value) value)
    (#f (error "missing key" key obj))))

(define (keys obj) (map car obj))

(define (systems fig) (vector->list (field fig 'systems)))

(define (system-ref fig s) (vector-ref (field fig 'systems) s))

(define (group-ref fig s g)
  (vector-ref (field (system-ref fig s) 'groups) g))

(define (voice-ref fig s g v)
  (vector-ref (field (group-ref fig s g) 'voices) v))

(define (events-of fig s g v)
  "The events of voice V of group G in system S, as a list."
  (vector->list (field (voice-ref fig s g v) 'events)))

(define (timing events)
  "Each event as (start dur lane continued)."
  (map (lambda (e)
         (list (field e 'start) (field e 'dur) (field e 'lane)
               (field e 'continued)))
       events))

(define (ev start dur lane text fill text-color continued)
  "An event object, keys in the documented order."
  `((start . ,start) (dur . ,dur) (lane . ,lane) (text . ,text)
    (fill . ,fill) (text_color . ,text-color) (continued . ,continued)))

(define (lanes-of fig s g)
  (field (group-ref fig s g) 'lanes))

(define (piece-of . lines)
  (read-piece-string (string-join lines "\n")))

(define (part-named piece name)
  (or (find (lambda (p) (eq? (part-name p) name)) (piece-parts piece))
      (error "no such part" name)))

(define (regroup piece . specs)
  "PIECE with its groups replaced by SPECS, each (LABEL SUBTITLE PART ...),
in that order: the groups v1 files wrote, which the notation no longer
has (ADR 0031)."
  (make-piece (piece-title piece)
              (piece-steps-per-pulse piece)
              (piece-steps-per-system piece)
              (piece-length piece)
              (piece-scales piece)
              (piece-instruments piece)
              (piece-parts piece)
              (map (match-lambda
                     ((label subtitle . names)
                      (make-group label subtitle
                                  (map (lambda (name) (part-named piece name))
                                       names)
                                  #f)))
                   specs)))

(define (instrument-named piece name)
  (find (lambda (i) (eq? (instrument-name i) name))
        (piece-instruments piece)))

(define (note-named instrument name)
  (find (lambda (n) (eq? (note-name n) name))
        (vector->list (instrument-notes instrument))))

(define (expected-look style piece instrument-name* note-name*)
  "The (text fill text_color) an event of that note should have, from
(notasi style), with fill #f as null, and text null: no note shows its
name in this slice."
  (let* ((instrument (instrument-named piece instrument-name*))
         (look (note-look style instrument
                          (note-named instrument note-name*))))
    (list 'null
          (or (look-fill look) 'null)
          (look-text-color look))))

(define (event-look e)
  (list (field e 'text) (field e 'fill) (field e 'text_color)))

(define figure-keys '(version title steps_per_pulse sizes systems caption))
(define sizes-keys '(label_width lane_width step_width row_height))
(define system-keys '(start steps groups))
(define group-keys '(label subtitle lanes voices))
(define voice-keys '(name events))
(define event-keys '(start dur lane text fill text_color continued))

(define (well-formed? fig)
  "Does every object in FIG have exactly the documented keys, in order,
and every array a vector?"
  (define (every-in vec ok?)
    (and (vector? vec) (every ok? (vector->list vec))))
  (define (event-ok? e) (equal? (keys e) event-keys))
  (define (voice-ok? v)
    (and (equal? (keys v) voice-keys)
         (string? (field v 'name))
         (every-in (field v 'events) event-ok?)))
  (define (group-ok? g)
    (and (equal? (keys g) group-keys)
         (every-in (field g 'lanes) string?)
         (every-in (field g 'voices) voice-ok?)))
  (define (system-ok? s)
    (and (equal? (keys s) system-keys)
         (every-in (field s 'groups) group-ok?)))
  (and (equal? (keys fig) figure-keys)
       (equal? (keys (field fig 'sizes)) sizes-keys)
       (every-in (field fig 'systems) system-ok?)))

(define white "#ffffff")
(define dark "#222222")
(define grey "#cccccc")              ; strokes (ADRs 0019, 0021)
;; pastel1 (the default, ADR 0021), degree k → colour k; all take dark text
(define ding-fill "#fbb4ae")
(define dong-fill "#b3cde3")
(define deng-fill "#ccebc5")
(define dung-fill "#decbe4")
(define dang-fill "#fed9a6")

(define selisir-lines
  '("(scale selisir"
    "  (ding :alias i :display \"i\")"
    "  (dong :alias o :display \"o\")"
    "  (deng :alias e :display \"e\")"
    "  (dung :alias u :display \"u\")"
    "  (dang :alias a :display \"a\"))"))

;;; ------------------------------------------------------------------
;;; Fixtures

;; A small piece used for the complete figure: two systems of 3 and 2
;; steps, a held note cut at step 3, a note ending exactly at step 3, a
;; chord, a group with a subtitle (built by hand) and a default stroke
;; group.
(define tiny
  (regroup
   (piece-of
    "(piece \"Tiny\" :steps-per-pulse 2 :steps-per-system 3)"
    "(scale selisir (ding :display \"i\") (dong :display \"o\") (deng :display \"e\"))"
    "(strokes gong-strokes G P)"
    "(instrument ugal selisir ding1 dong1 deng1 ding2)"
    "(instrument gong gong-strokes G P)"
    "(part ugal :name polos    1 _ 2 _ _)"
    "(part ugal :name sangsih  - 4 _ (1 3) -)"
    "(part gong                2 - - 1 -)")
   '("Ugal" "polos + sangsih" polos sangsih)
   '("gong" #f gong)))

(define (sys start steps . groups)
  `((start . ,start) (steps . ,steps) (groups . ,(list->vector groups))))

(define (grp label subtitle lanes . voices)
  `((label . ,label) (subtitle . ,subtitle) (lanes . ,lanes)
    (voices . ,(list->vector voices))))

(define (voice name . events)
  `((name . ,name) (events . ,(list->vector events))))

;; Lanes of "Ugal": ding2 deng1 dong1 ding1 → i2 e1 o1 i1 (0 1 2 3).
;; No note shows its name: text is null for pitched notes and strokes.
;; Lanes of "gong": G P (0 1).
(define tiny-expected
  `((version . 1)
    (title . "Tiny")
    (steps_per_pulse . 2)
    (sizes . ((label_width . "10.5em")   ; "polos + sangsih": 15 chars
              (lane_width . "2.0em")     ; "i2": 2 chars
              (step_width . "2.0em")
              (row_height . "2.0em")))
    (systems
     . ,(vector
         (sys 0 3
              (grp "Ugal" "polos + sangsih" #("i2" "e1" "o1" "i1")
                   (voice "polos"
                          (ev 0 2 3 'null ding-fill dark #f)
                          (ev 2 1 2 'null dong-fill dark #f))
                   (voice "sangsih"
                          (ev 1 2 0 'null ding-fill dark #f)))
              (grp "gong" 'null #("G" "P")
                   (voice "gong"
                          (ev 0 1 1 'null grey dark #f))))
         (sys 3 2
              (grp "Ugal" "polos + sangsih" #("i2" "e1" "o1" "i1")
                   (voice "polos"
                          (ev 0 2 2 'null dong-fill dark #t))
                   (voice "sangsih"
                          (ev 0 1 1 'null deng-fill dark #f)
                          (ev 0 1 3 'null ding-fill dark #f)))
              (grp "gong" 'null #("G" "P")
                   (voice "gong"
                          (ev 0 1 0 'null grey dark #f))))))
    (caption . null)))

;; Pieces of 10 steps with various steps-per-system.
(define (ten-steps . options)
  (apply piece-of
         (append
          (list (string-append "(piece \"Ten\" "
                               (string-join options " ")
                               ")")
                "(scale s a b)"
                "(strokes k-strokes K)"
                "(instrument u s a1 b1)"
                "(instrument kempli k-strokes K)"
                "(part u :name melody  1 2 1 2 1 2 1 2 1 2)"
                "(part u :name rests   1 - - - - - - - - -)"
                "(part kempli          K - K - K - K - K -)"))))

;; Held notes against systems of 4 steps (16 steps, 4 systems).
(define cuts
  (piece-of
   "(piece \"Cuts\" :steps-per-pulse 2 :steps-per-system 4)"
   "(scale s (ding :display \"i\") (dong :display \"o\"))"
   "(instrument u s ding1 dong1)"
   ;; ding1 at 2 for 4 steps: crosses step 4.
   "(part u :name one    - - 1 _ / _ _ - - / - - - - / - - - -)"
   ;; ding1 at 3 for 6 steps: crosses steps 4 and 8.
   "(part u :name two    - - - 1 / _ _ _ _ / _ - - - / - - - -)"
   ;; ends on step 4; starts on step 4; inside; last step.
   "(part u :name edges  1 _ _ _ / 2 _ - - / - 1 _ _ / - - - 2)"
   ;; the whole piece.
   "(part u :name whole  1 _ _ _ / _ _ _ _ / _ _ _ _ / _ _ _ _)"
   ;; a chord at 3 for 2 steps.
   "(part u :name chord  - - - (1 2) / _ - - - / - - - - / - - - -)"))

;; Groups of one part and of several, pitched and stroke: the groups v1
;; wrote ("Reyong-ish", "Colotomic") and its default groups, in v1's
;; order, built by hand.
(define (groups-piece . options)
  (regroup
   (apply piece-of
          (append
           (list (string-append "(piece \"Groups\" "
                                (string-join options " ") ")"))
           selisir-lines
           (list
            "(strokes kempli-strokes K)"
            "(strokes gong-strokes G P)"
            "(instrument ugal selisir o1 e1 u1 a1 i2 o2 e2)"
            "(instrument kempli kempli-strokes K)"
            "(instrument gong gong-strokes G P)"
            "(part ugal :name melody   a1 o2 i2 e2)"
            "(part kempli              K  K  K  K)"
            "(part ugal :name polos    i2 -  e2 -)"
            "(part ugal :name sangsih  -  u1 -  o2)"
            "(part gong                P  -  G  -)"
            "(part ugal :name silent   -  -  -  -)")))
   '("melody" #f melody)
   '("Colotomic" #f gong kempli)
   '("Reyong-ish" "sangsih + polos" sangsih polos)
   '("silent" #f silent)))

(define tenzer (read-piece-file "examples/tenzer1.nts"))

(define (sizes-of . lines)
  (field (layout-piece (apply piece-of lines)) 'sizes))

;;; ------------------------------------------------------------------

(test-begin "layout")

;;; ------------------------------------------------------------------
;;; The figure's top level

(test-group "figure top level"
  (test-equal "keys in the documented order"
    figure-keys
    (keys (layout-piece tiny)))
  (test-equal "version 1" 1 (field (layout-piece tiny) 'version))
  (test-equal "title is the piece's title"
    "Tiny" (field (layout-piece tiny) 'title))
  (test-equal "steps_per_pulse from the piece"
    2 (field (layout-piece tiny) 'steps_per_pulse))
  (test-equal "steps_per_pulse defaults to the piece's default (4)"
    4 (field (layout-piece (ten-steps)) 'steps_per_pulse))
  (test-equal "tenzer1: steps_per_pulse 1"
    1 (field (layout-piece tenzer) 'steps_per_pulse))
  (test-equal "tenzer1: title"
    "Eight-pulse gong cycle" (field (layout-piece tenzer) 'title))
  (test-eq "caption is the symbol null"
    'null (field (layout-piece tiny) 'caption))
  (test-assert "systems is a vector"
    (vector? (field (layout-piece tiny) 'systems)))
  (test-assert "every object has its keys in order, arrays are vectors"
    (well-formed? (layout-piece tiny)))
  (test-assert "well-formed: groups piece"
    (well-formed? (layout-piece (groups-piece ":steps-per-system 3"))))
  (test-assert "well-formed: tenzer1"
    (well-formed? (layout-piece tenzer)))
  (test-assert "json-string accepts the figure"
    (string? (json-string (layout-piece tiny))))
  (test-assert "json-string accepts the figure (compact)"
    (string? (json-string (layout-piece tenzer) #:pretty? #f)))
  (test-assert "json-string accepts a figure with no systems"
    (string? (json-string (layout-piece (piece-of "(piece \"Empty\")")))))
  (test-equal "style left out = (default-style)"
    (layout-piece tenzer #:style (default-style))
    (layout-piece tenzer)))

;;; ------------------------------------------------------------------
;;; Sizes

(test-group "sizes"
  (test-equal "the prototype: \"polos + sangsih\" → 10.5em, \"neng1\" → 3.6em"
    '((label_width . "10.5em") (lane_width . "3.6em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (field
     (layout-piece
      (regroup
       (piece-of
        "(piece \"Reyong kotekan\")"
        "(scale reyong-4 nang ning nong neng)"
        "(instrument reyong reyong-4 nang1 ning1 nong1 neng1)"
        "(part reyong :name polos    1 _ 1 2 / _ 1 2 _ / 2 1 _ 2)"
        "(part reyong :name sangsih  4 3 4 _ / 3 4 _ 3 / _ 4 3 _)")
       '("Reyong" "polos + sangsih" polos sangsih)))
     'sizes))

  (test-equal "no groups: 1.5em and 1.0em"
    '((label_width . "1.5em") (lane_width . "1.0em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (sizes-of "(piece \"Empty\")"))

  (test-equal "one-letter label and stroke: 2.1em, 1.5em"
    '((label_width . "2.1em") (lane_width . "1.5em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (sizes-of "(piece \"P\")"
              "(strokes k-strokes K)"
              "(instrument kempli k-strokes K)"
              "(part kempli :name x K -)"))

  (test-equal "lane label of 4 chars: 3.08 rounds up to 3.1em"
    "3.1em"
    (field (sizes-of "(piece \"P\")"
                     "(scale s (a :display \"abc\"))"
                     "(instrument u s a1)"
                     "(part u :name x 1)")
           'lane_width))

  (test-equal "lane label of 7 chars: 4.64 rounds down to 4.6em"
    "4.6em"
    (field (sizes-of "(piece \"P\")"
                     "(scale s (a :display \"abcdef\"))"
                     "(instrument u s a1)"
                     "(part u :name x 1)")
           'lane_width))

  (test-equal "lane label of 9 chars: 5.68 rounds up to 5.7em"
    "5.7em"
    (field (sizes-of "(piece \"P\")"
                     "(scale s (a :display \"abcdefgh\"))"
                     "(instrument u s a1)"
                     "(part u :name x 1)")
           'lane_width))

  (test-equal "degree name without display: \"dong2\" → 3.6em"
    "3.6em"
    (field (sizes-of "(piece \"P\")"
                     "(scale s ding dong)"
                     "(instrument u s ding2 dong2)"
                     "(part u :name x 2)")
           'lane_width))

  (test-equal "a subtitle longer than every label counts (20 chars → 13.5em)"
    "13.5em"
    (field (field (layout-piece
            (regroup (piece-of "(piece \"P\")"
                               "(strokes k-strokes K)"
                               "(instrument kempli k-strokes K)"
                               "(part kempli :name a K)"
                               "(part kempli :name b K)")
                     '("a" #f a)
                     '("Bb" "twenty chars long xx" b)))
           'sizes)
           'label_width))

  (test-equal "longest label over all groups (the last one here)"
    "6.3em"                             ; "Eight ch": 8 chars
    (field (field (layout-piece
            (regroup (piece-of "(piece \"P\")"
                               "(strokes k-strokes K)"
                               "(instrument kempli k-strokes K)"
                               "(part kempli :name a K)"
                               "(part kempli :name b K)")
                     '("a" #f a)
                     '("Eight ch" #f b)))
           'sizes)
           'label_width))

  (test-equal "longest lane label over all groups (not the first)"
    "4.6em"                             ; "abcdef1" in group y
    (field (sizes-of "(piece \"P\")"
                     "(scale s a (b :display \"abcdef\"))"
                     "(instrument u s a1 b1)"
                     "(part u :name x 1)"
                     "(part u :name y 2)")
           'lane_width))

  (test-equal "characters, not bytes: \"Kempli · Gong\" → 9.3em"
    "9.3em"
    (field (field (layout-piece
            (regroup (piece-of "(piece \"P\")"
                               "(strokes k-strokes K)"
                               "(instrument kempli k-strokes K)"
                               "(part kempli :name a K)")
                     '("Kempli · Gong" #f a)))
           'sizes)
           'label_width))

  (test-equal "a group of rests adds no lane label"
    '((label_width . "2.7em") (lane_width . "1.0em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (sizes-of "(piece \"P\")"
              "(scale s a)"
              "(instrument u s a1)"
              "(part u :name ab - -)"))

  (test-equal "tenzer1: \"kempli\" → 5.1em, \"e2\" → 2.0em"
    '((label_width . "5.1em") (lane_width . "2.0em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (field (layout-piece tenzer) 'sizes))

  (test-equal "sizes are the same with and without systems breaks"
    (field (layout-piece (groups-piece)) 'sizes)
    (field (layout-piece (groups-piece ":steps-per-system 1")) 'sizes))

  (test-equal "groups piece: \"sangsih + polos\" → 10.5em, \"e2\" → 2.0em"
    '((label_width . "10.5em") (lane_width . "2.0em")
      (step_width . "2.0em") (row_height . "2.0em"))
    (field (layout-piece (groups-piece)) 'sizes)))

;;; ------------------------------------------------------------------
;;; Systems

(define (starts+steps fig)
  (map (lambda (s) (list (field s 'start) (field s 'steps))) (systems fig)))

(test-group "systems"
  (test-equal "no steps-per-system: one system of the whole piece"
    '((0 10))
    (starts+steps (layout-piece (ten-steps))))
  (test-equal "steps-per-system 5 divides 10: two systems"
    '((0 5) (5 5))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 5"))))
  (test-equal "steps-per-system 4: the last system is shorter"
    '((0 4) (4 4) (8 2))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 4"))))
  (test-equal "steps-per-system 3: starts are absolute"
    '((0 3) (3 3) (6 3) (9 1))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 3"))))
  (test-equal "steps-per-system 1: one system per step"
    (map (lambda (i) (list i 1)) (iota 10))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 1"))))
  (test-equal "steps-per-system 12 > length 10: one system of 10"
    '((0 10))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 12"))))
  (test-equal "steps-per-system 10 = length: one system"
    '((0 10))
    (starts+steps (layout-piece (ten-steps ":steps-per-system 10"))))
  (test-equal "tenzer1: one system of 9 steps"
    '((0 9))
    (starts+steps (layout-piece tenzer)))

  (test-equal "a piece of length 0 (no parts) has no systems"
    #()
    (field (layout-piece (piece-of "(piece \"Empty\")")) 'systems))
  (test-equal "a piece of length 0 with a group has no systems"
    #()
    (field (layout-piece (piece-of "(piece \"Zero\")"
                                   "(scale s a)"
                                   "(instrument u s a1)"
                                   "(part u :name p /)"))
           'systems))
  (test-equal "a piece of length 0 with steps-per-system has no systems"
    #()
    (field (layout-piece (piece-of "(piece \"Zero\" :steps-per-system 4)"
                                   "(scale s a)"
                                   "(instrument u s a1)"
                                   "(part u :name p /)"))
           'systems))

  (test-equal "every group in every system, in piece order"
    (make-list 3 '("melody" "rests" "kempli"))
    (map (lambda (s)
           (map (lambda (g) (field g 'label))
                (vector->list (field s 'groups))))
         (systems (layout-piece (ten-steps ":steps-per-system 4")))))
  (test-equal "a voice with nothing in a system has events #()"
    '(1 0 0)
    (map (lambda (s) (length (events-of (layout-piece
                                         (ten-steps ":steps-per-system 4"))
                                        s 1 0)))
         '(0 1 2)))
  (test-equal "the empty voice is #(), not '()"
    #()
    (field (voice-ref (layout-piece (ten-steps ":steps-per-system 4")) 2 1 0)
           'events))
  (test-equal "events split by system, starts relative"
    '(((0 1 0 #f) (2 1 0 #f))
      ((0 1 0 #f) (2 1 0 #f))
      ((0 1 0 #f)))
    (map (lambda (s)
           (timing (events-of (layout-piece (ten-steps ":steps-per-system 4"))
                              s 2 0)))
         '(0 1 2))))

;;; ------------------------------------------------------------------
;;; Cut events

(test-group "cut events"
  ;; Groups in cuts: one two edges whole chord (default groups, one voice).
  (test-equal "crossing one boundary: two pieces, continued #f then #t"
    '(((2 2 0 #f)) ((0 2 0 #t)) () ())
    (map (lambda (s) (timing (events-of (layout-piece cuts) s 0 0)))
         '(0 1 2 3)))
  (test-equal "crossing two boundaries: three pieces"
    '(((3 1 0 #f)) ((0 4 0 #t)) ((0 1 0 #t)) ())
    (map (lambda (s) (timing (events-of (layout-piece cuts) s 1 0)))
         '(0 1 2 3)))
  (test-equal "ending on or starting on a boundary: not cut"
    ;; lanes of edges: dong1 (0), ding1 (1)
    '(((0 4 1 #f)) ((0 2 0 #f)) ((1 3 1 #f)) ((3 1 0 #f)))
    (map (lambda (s) (timing (events-of (layout-piece cuts) s 2 0)))
         '(0 1 2 3)))
  (test-equal "a note through the whole piece: one piece per system"
    '(((0 4 0 #f)) ((0 4 0 #t)) ((0 4 0 #t)) ((0 4 0 #t)))
    (map (lambda (s) (timing (events-of (layout-piece cuts) s 3 0)))
         '(0 1 2 3)))
  (test-equal "a chord crossing a boundary: every note cut"
    ;; lanes of chord: dong1 (0), ding1 (1)
    '(((3 1 0 #f) (3 1 1 #f)) ((0 1 0 #t) (0 1 1 #t)) () ())
    (map (lambda (s) (timing (events-of (layout-piece cuts) s 4 0)))
         '(0 1 2 3)))
  (test-equal "every piece of a cut note keeps its text and look"
    (list (list 'null ding-fill dark) (list 'null ding-fill dark)
          (list 'null ding-fill dark))
    (map (lambda (s) (event-look (car (events-of (layout-piece cuts) s 1 0))))
         '(0 1 2)))
  (test-equal "the full event objects of a cut note"
    (list (ev 2 2 0 'null ding-fill dark #f)
          (ev 0 2 0 'null ding-fill dark #t))
    (append (events-of (layout-piece cuts) 0 0 0)
            (events-of (layout-piece cuts) 1 0 0)))
  (test-equal "without systems breaks nothing is cut"
    '((3 6 0 #f))
    (timing (events-of (layout-piece
                        (piece-of "(piece \"P\")"
                                  "(scale s a)"
                                  "(instrument u s a1)"
                                  "(part u :name two - - - 1 _ _ _ _ _ - - - - - - -)"))
                       0 0 0))))

;;; ------------------------------------------------------------------
;;; Groups and lanes

(define (group-labels fig s)
  (map (lambda (g) (field g 'label))
       (vector->list (field (system-ref fig s) 'groups))))

(define (voice-names fig s g)
  (map (lambda (v) (field v 'name))
       (vector->list (field (group-ref fig s g) 'voices))))

(test-group "groups and lanes"
  (test-equal "written and default groups in the piece's order"
    '("melody" "Colotomic" "Reyong-ish" "silent")
    (group-labels (layout-piece (groups-piece)) 0))
  (test-equal "group order follows piece-groups"
    (map group-label (piece-groups (groups-piece)))
    (group-labels (layout-piece (groups-piece)) 0))
  (test-equal "subtitle: a string or null"
    '(null null "sangsih + polos" null)
    (map (lambda (g) (field (group-ref (layout-piece (groups-piece)) 0 g)
                            'subtitle))
         '(0 1 2 3)))
  (test-equal "lanes: pitched notes used, highest first"
    #("e2" "o2" "i2" "a1")
    (lanes-of (layout-piece (groups-piece)) 0 0))
  (test-equal "lanes: union of the group's parts, highest first"
    #("e2" "o2" "i2" "u1")
    (lanes-of (layout-piece (groups-piece)) 0 2))
  (test-equal "lanes: strokes in instrument order, instruments in part order"
    #("G" "P" "K")
    (lanes-of (layout-piece (groups-piece)) 0 1))
  (test-equal "lanes: a group of rests has none"
    #()
    (lanes-of (layout-piece (groups-piece)) 0 3))
  (test-equal "lanes are note-label of group-lanes"
    (map (lambda (g)
           (list->vector
            (map (lambda (note)
                   (note-label (part-instrument (car (group-parts g))) note))
                 (group-lanes g))))
         (filter (lambda (g) (not (equal? (group-label g) "Colotomic")))
                 (piece-groups (groups-piece))))
    (map (lambda (g) (lanes-of (layout-piece (groups-piece)) 0 g))
         '(0 2 3)))
  (test-equal "the same lanes in every system"
    (make-list 4 (list #("e2" "o2" "i2" "a1") #("G" "P" "K")
                       #("e2" "o2" "i2" "u1") #()))
    (map (lambda (s)
           (map (lambda (g) (lanes-of (layout-piece
                                       (groups-piece ":steps-per-system 1"))
                                      s g))
                '(0 1 2 3)))
         '(0 1 2 3)))
  (test-equal "voices: one per part, in the group's part order, as strings"
    '(("melody") ("gong" "kempli") ("sangsih" "polos") ("silent"))
    (map (lambda (g) (voice-names (layout-piece (groups-piece)) 0 g))
         '(0 1 2 3)))
  (test-equal "voices in every system, even when empty"
    (make-list 2 '(("melody") ("gong" "kempli") ("sangsih" "polos")
                   ("silent")))
    (map (lambda (s)
           (map (lambda (g) (voice-names (layout-piece
                                          (groups-piece ":steps-per-system 2"))
                                         s g))
                '(0 1 2 3)))
         '(0 1)))
  (test-equal "lane index: melody a1 o2 i2 e2"
    '((0 1 3 #f) (1 1 1 #f) (2 1 2 #f) (3 1 0 #f))
    (timing (events-of (layout-piece (groups-piece)) 0 0 0)))
  (test-equal "lane index: strokes of two instruments"
    '(((0 1 1 #f) (2 1 0 #f))
      ((0 1 2 #f) (1 1 2 #f) (2 1 2 #f) (3 1 2 #f)))
    (list (timing (events-of (layout-piece (groups-piece)) 0 1 0))
          (timing (events-of (layout-piece (groups-piece)) 0 1 1))))
  (test-equal "lane index: two parts sharing lanes"
    '(((1 1 3 #f) (3 1 1 #f))
      ((0 1 2 #f) (2 1 0 #f)))
    (list (timing (events-of (layout-piece (groups-piece)) 0 2 0))
          (timing (events-of (layout-piece (groups-piece)) 0 2 1))))
  (test-equal "a silent voice has events #()"
    #()
    (field (voice-ref (layout-piece (groups-piece)) 0 3 0) 'events))
  (test-equal "second system of two: relative starts, all lanes kept"
    '(((0 1 2 #f) (1 1 0 #f))          ; melody i2 e2
      ((0 1 0 #f))                     ; gong G
      ((0 1 2 #f) (1 1 2 #f))          ; kempli
      ((1 1 1 #f))                     ; sangsih o2
      ((0 1 0 #f))                     ; polos e2
      ())                              ; silent
    (let ((fig (layout-piece (groups-piece ":steps-per-system 2"))))
      (map (lambda (gv) (timing (apply events-of fig 1 gv)))
           '((0 0) (1 0) (1 1) (2 0) (2 1) (3 0))))))

;;; ------------------------------------------------------------------
;;; Events

(test-group "events"
  (test-equal "start and dur of notes and holds"
    '((0 3 1 #f) (3 1 0 #f) (4 2 1 #f))
    (timing (events-of (layout-piece
                        (piece-of "(piece \"P\")"
                                  "(scale s a b)"
                                  "(instrument u s a1 b1)"
                                  "(part u :name p 1 _ _ 2 1 _ -)"))
                       0 0 0)))
  (test-equal "a chord: one event per note, same start and dur, by lane"
    ;; lanes: b1 (0), a1 (1); chord (1 2) at 0 for 2, then 2 at 2
    '((0 2 0 #f) (0 2 1 #f) (2 1 0 #f))
    (timing (events-of (layout-piece
                        (piece-of "(piece \"P\")"
                                  "(scale s a b)"
                                  "(instrument u s a1 b1)"
                                  "(part u :name p (1 2) _ 2)"))
                       0 0 0)))
  (test-equal "a chord written high-to-low is still sorted by lane"
    '((0 1 0 #f) (0 1 1 #f) (0 1 2 #f))
    (timing (events-of (layout-piece
                        (piece-of "(piece \"P\")"
                                  "(scale s a b c)"
                                  "(instrument u s a1 b1 c1)"
                                  "(part u :name p (c1 a1 b1))"))
                       0 0 0)))
  (test-equal "a stroke chord: lanes in instrument order"
    '((0 1 0 #f) (0 1 1 #f) (1 1 2 #f))
    (timing (events-of (layout-piece
                        (piece-of "(piece \"P\")"
                                  "(strokes k dag dug du)"
                                  "(instrument kendang k dag dug du)"
                                  "(part kendang :name p (dug dag) du)"))
                       0 0 0)))

  (test-equal "no note shows its name: text null, colours kept"
    (list (ev 0 1 0 'null dung-fill dark #f)
          (ev 1 1 1 'null dang-fill dark #f))
    (events-of (layout-piece
                (apply piece-of
                       (append '("(piece \"P\")") selisir-lines
                               '("(instrument u selisir a1 u2)"
                                 "(part u :name p u2 a1)"))))
               0 0 0))
  (test-equal "strokes show no name either: grey boxes, text null"
    (list (ev 0 1 0 'null grey dark #f))
    (events-of (layout-piece
                (piece-of "(piece \"P\")"
                          "(strokes k dag)"
                          "(instrument kendang k dag)"
                          "(part kendang :name p dag)"))
               0 0 0))
  (test-equal "default style, hard-coded: selisir degrees in pastel1"
    (list (ev 0 1 0 'null dung-fill dark #f)
          (ev 1 1 1 'null deng-fill dark #f)
          (ev 2 1 2 'null dong-fill dark #f)
          (ev 3 1 3 'null ding-fill dark #f)
          (ev 4 1 4 'null dang-fill dark #f))
    (events-of (layout-piece
                (apply piece-of
                       (append '("(piece \"P\")") selisir-lines
                               '("(instrument u selisir a1 i2 o2 e2 u2)"
                                 "(part u :name p u2 e2 o2 i2 a1)"))))
               0 0 0))
  (test-equal "degree without :display: the lane label is the degree name"
    #("dong1")
    (lanes-of (layout-piece (piece-of "(piece \"P\")"
                                      "(scale s ding dong)"
                                      "(instrument u s ding1 dong1)"
                                      "(part u :name p 2)"))
              0 0))
  (test-equal "a selisir with :display \"i\" labels its lane \"i1\", not \"ding1\""
    #("i1")
    (lanes-of (layout-piece
               (piece-of "(piece \"P\")"
                         "(scale selisir (ding :display \"i\") dong)"
                         "(instrument u selisir ding1 dong1)"
                         "(part u :name p ding1)"))
              0 0))
  (test-equal "strokes: grey, text null, text colour #222222 (ADR 0019)"
    (list (ev 0 1 0 'null grey dark #f)
          (ev 1 1 1 'null grey dark #f))
    (events-of (layout-piece
                (piece-of "(piece \"P\")"
                          "(strokes k (dag :display \"D\") dug du)"
                          "(instrument kendang k dag dug du)"
                          "(part kendang :name p dag dug)"))
               0 0 0))
  (test-equal "strokes: lanes show the display form"
    #("D" "dug")
    (lanes-of (layout-piece
               (piece-of "(piece \"P\")"
                         "(strokes k (dag :display \"D\") dug du)"
                         "(instrument kendang k dag dug du)"
                         "(part kendang :name p dag dug)"))
              0 0))

  (test-equal "custom palette via #:style (set1)"
    (list (list 'null "#e41a1c" white) (list 'null "#377eb8" white))
    (map event-look
         (events-of (layout-piece
                     (apply piece-of
                            (append '("(piece \"P\")") selisir-lines
                                    '("(instrument u selisir i2 o2)"
                                      "(part u :name p i2 o2)")))
                     #:style (make-style #:palette 'set1))
                    0 0 0)))
  (test-equal "custom degree-colors via #:style"
    (list (list 'null ding-fill dark) (list 'null "#000000" white))
    (map event-look
         (events-of (layout-piece
                     (apply piece-of
                            (append '("(piece \"P\")") selisir-lines
                                    '("(instrument u selisir i2 o2)"
                                      "(part u :name p i2 o2)")))
                     #:style (make-style
                              #:degree-colors '((dong . "#000000"))))
                    0 0 0)))
  ;; Its fill and text colour are used as they are; its text is not,
  ;; since no note shows its name in this slice.
  (test-equal "custom scheme via #:style: its look used as is"
    (list (ev 0 1 0 'null 'null "#123456" #f)
          (ev 1 1 1 'null 'null "#123456" #f))
    (events-of (layout-piece
                (piece-of "(piece \"P\")"
                          "(scale s a b)"
                          "(instrument u s a1 b1)"
                          "(part u :name p 2 1)")
                #:style (make-style
                         #:scheme (lambda (style instrument note)
                                    (make-look #f "x" "#123456"))))
               0 0 0))
  (test-equal "looks match note-look for every event (pastel2 style)"
    (let ((style (make-style #:palette 'pastel2)))
      (map (lambda (name) (expected-look style tenzer 'ugal name))
           '(dang1 dong2 ding2 deng2 dong2 dang1 dong2 ding2 dang1)))
    (map event-look
         (events-of (layout-piece tenzer
                                  #:style (make-style #:palette 'pastel2))
                    0 0 0)))

  (test-equal "tenzer1: one default group per part, in part order"
    '("ugal" "kempli" "gong")
    (group-labels (layout-piece tenzer) 0))
  (test-equal "tenzer1: lanes of the three groups"
    (list #("e2" "o2" "i2" "a1") #("K") #("G" "P"))
    (map (lambda (g) (lanes-of (layout-piece tenzer) 0 g)) '(0 1 2)))
  (test-equal "tenzer1: labels, subtitles and voice names"
    '(("ugal" null ("ugal"))
      ("kempli" null ("kempli"))
      ("gong" null ("gong")))
    (map (lambda (g)
           (let ((group (group-ref (layout-piece tenzer) 0 g)))
             (list (field group 'label) (field group 'subtitle)
                   (voice-names (layout-piece tenzer) 0 g))))
         '(0 1 2)))
  (test-equal "tenzer1: the ugal's events: colours, no names"
    (list (ev 0 1 3 'null dang-fill dark #f)
          (ev 1 1 1 'null dong-fill dark #f)
          (ev 2 1 2 'null ding-fill dark #f)
          (ev 3 1 0 'null deng-fill dark #f)
          (ev 4 1 1 'null dong-fill dark #f)
          (ev 5 1 3 'null dang-fill dark #f)
          (ev 6 1 1 'null dong-fill dark #f)
          (ev 7 1 2 'null ding-fill dark #f)
          (ev 8 1 3 'null dang-fill dark #f))
    (events-of (layout-piece tenzer) 0 0 0))
  (test-equal "tenzer1: kempli on every step"
    (map (lambda (i) (ev i 1 0 'null grey dark #f)) (iota 9))
    (events-of (layout-piece tenzer) 0 1 0))
  (test-equal "tenzer1: gong and kempur"
    (list (ev 0 1 0 'null grey dark #f)
          (ev 4 1 0 'null grey dark #f)
          (ev 5 1 1 'null grey dark #f)
          (ev 7 1 1 'null grey dark #f)
          (ev 8 1 0 'null grey dark #f))
    (events-of (layout-piece tenzer) 0 2 0)))

;;; ------------------------------------------------------------------
;;; A complete figure

(test-group "complete figure"
  (test-equal "tiny: the whole figure, written out"
    tiny-expected
    (layout-piece tiny))
  (test-equal "tiny: same with an explicit default style"
    tiny-expected
    (layout-piece tiny #:style (default-style))))

(define runner (test-runner-current))
(test-end "layout")

(exit (zero? (+ (test-runner-fail-count runner)
                (test-runner-xpass-count runner))))
