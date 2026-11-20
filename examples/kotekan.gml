;; Reyong kotekan: polos and sangsih interlocking over four pots, with
;; the gong at the start of the cycle. A textbook excerpt, one line,
;; as in doc/design/01-notation.md.
;;
;; The source names the four pots by syllable: nang ning nong neng
;; (do mi fa sol). Twelve steps, four to a pulse, drawn in systems of
;; eight steps. Sangsih's nong on step 8 (the last step of the second
;; pulse) is held into step 9, so it is cut across the two systems.

(piece "Reyong kotekan"
  (steps-per-pulse 4)
  (steps-per-system 8))

(scale reyong-4  nang ning nong neng)
(strokes gong-strokes  G)

(instrument reyong reyong-4  nang1 ning1 nong1 neng1)
(instrument gong   gong-strokes G (show-names yes))

(part polos   reyong  1 _ 1 2 / _ 1 2 _ / 2 1 _ 2)
(part sangsih reyong  4 3 4 _ / 3 4 _ 3 / _ 4 3 _)
(part gong    gong    1 - - - / - - - - / - - - -)

(group "Reyong" polos sangsih (subtitle "polos + sangsih"))
