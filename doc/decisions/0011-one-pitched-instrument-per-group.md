# 0011 One pitched instrument per group

Status: accepted (2026-11-20)

Context: A `group` draws several parts in one block of rows that share lanes. The design did not say whether those parts could be on different instruments. With two pitched instruments in one group, e.g. ugal and reyong, it is unclear whether both instruments' `ding2` share one lane or get one each, and `group-lanes` cannot just return note records, because notes from two instruments with different ranges would have to be merged. Grouping stroke instruments is clearly useful, e.g. kempli and gong in the prototype.

Decision: All pitched parts in a group play the same instrument. Grouping different pitched instruments together is a reader error. Parts on different stroke instruments may share a group. This is invariant 6 in `02-piece.md`.

Consequences: `group-lanes` returns plain note records, and a group's pitched lanes are one instrument's notes, sorted highest first. To compare two pitched instruments, draw them as separate groups. Whether a group may mix a pitched instrument with stroke instruments, and whether same-named strokes from two stroke instruments share a lane, are still open questions in `02-piece.md`.
