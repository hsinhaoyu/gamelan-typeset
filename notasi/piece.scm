;;; (notasi piece) -- Records for a gamelan piece: scales, instruments,
;;; notes, parts, events and groups.  See doc/design/02-piece.md.
;;;
;;; The records are immutable.  Constructors do not validate: the reader
;;; checks the invariants, and everything downstream assumes them.

(define-module (notasi piece)
  #:use-module (srfi srfi-9)
  #:export (make-source-location source-location?
            source-location-file source-location-line

            make-piece piece?
            piece-title piece-steps-per-pulse piece-steps-per-system
            piece-length piece-scales piece-instruments piece-parts
            piece-groups

            make-scale scale?
            scale-name scale-degrees scale-pitched? scale-location

            make-degree degree?
            degree-name degree-aliases degree-display degree-location

            make-instrument instrument?
            instrument-name instrument-scale instrument-notes
            instrument-location

            make-note note?
            note-name note-degree note-octave

            make-part part?
            part-name part-instrument part-events part-location

            make-event event?
            event-start event-duration event-notes

            make-group group?
            group-label group-subtitle group-parts group-location))

;;; Where a record came from, for error messages.  FILE is #f when the
;;; source was a string or port; LINE is 1-based.
(define-record-type <source-location>
  (make-source-location file line)
  source-location?
  (file source-location-file)
  (line source-location-line))

;;; A whole piece after reading, with templates merged.
(define-record-type <piece>
  (make-piece title steps-per-pulse steps-per-system length
              scales instruments parts groups)
  piece?
  (title            piece-title)
  (steps-per-pulse  piece-steps-per-pulse)
  (steps-per-system piece-steps-per-system) ; #f = one system
  (length           piece-length)           ; total steps
  (scales           piece-scales)           ; includes stroke sets
  (instruments      piece-instruments)
  (parts            piece-parts)
  (groups           piece-groups))

;;; A scale (pitched? #t, degrees ascending within one octave) or a
;;; stroke set (pitched? #f, strokes unordered).
(define-record-type <scale>
  (make-scale name degrees pitched? location)
  scale?
  (name     scale-name)
  (degrees  scale-degrees)
  (pitched? scale-pitched?)
  (location scale-location))

;;; A scale degree or a stroke.  DISPLAY is always a string; the reader
;;; fills in the name when the source gives none.
(define-record-type <degree>
  (make-degree name aliases display location)
  degree?
  (name     degree-name)
  (aliases  degree-aliases)
  (display  degree-display)
  (location degree-location))

;;; NOTES is a vector: ascending pitch for a pitched instrument, the
;;; listed order for a stroke instrument.
(define-record-type <instrument>
  (make-instrument name scale notes location)
  instrument?
  (name     instrument-name)
  (scale    instrument-scale)
  (notes    instrument-notes)
  (location instrument-location))

;;; DEGREE indexes the scale's degrees; OCTAVE is #f for a stroke.
(define-record-type <note>
  (make-note name degree octave)
  note?
  (name   note-name)
  (degree note-degree)
  (octave note-octave))

;;; EVENTS are sorted by start.
(define-record-type <part>
  (make-part name instrument events location)
  part?
  (name       part-name)
  (instrument part-instrument)
  (events     part-events)
  (location   part-location))

;;; NOTES are 0-based indices into the instrument's notes; more than one
;;; is a chord.
(define-record-type <event>
  (make-event start duration notes)
  event?
  (start    event-start)
  (duration event-duration)
  (notes    event-notes))

;;; LOCATION is #f for a default group (a part with no `group` form).
(define-record-type <group>
  (make-group label subtitle parts location)
  group?
  (label    group-label)
  (subtitle group-subtitle)
  (parts    group-parts)
  (location group-location))
