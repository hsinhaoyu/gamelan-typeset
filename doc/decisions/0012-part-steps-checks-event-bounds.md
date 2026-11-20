# 0012 part-steps checks event bounds, not part length

Status: accepted (2026-11-20)

Context: `(part-steps part)` returns the end of a part's last event. The design said it was "used for validation" but also that the reader checks part lengths from token counts, leaving its purpose unclear. It cannot measure a part's written length: rests are not stored, so a part written `1 - 2 - - -` has 6 steps but its last event ends at step 3. Using it for the equal-length check would accept parts of different lengths whenever one ends in rests.

Decision: `part-steps` is the reader's check for invariant 1, that every event lies within the piece (`part-steps` ≤ `piece-length`). The reader checks that parts have equal length from their token counts, while reading, because only the tokens record trailing rests. The piece does not store a part's written length.

Consequences: Nothing downstream should treat `part-steps` as a part's length; use `piece-length`. If looping parts (open question 1 in 01-notation.md) need a part's own length, `part` will need a new field, and that will need a new ADR.
