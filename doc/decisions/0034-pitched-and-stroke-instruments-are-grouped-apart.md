# 0034 Pitched and stroke instruments are grouped apart

Status: accepted (2026-11-21)

Context: ADR 0011 allows one pitched instrument per group and any number of stroke instruments, but left open whether a group may mix a pitched instrument with stroke instruments (e.g. ugal with kempli), and `group-lanes` didn't say where the stroke lanes would go.

Decision: A group's parts are either all pitched, on one instrument (ADR 0011), or all on stroke instruments. Mixing the two in one group is a reader error.

Consequences: A group's rows are one instrument's pitches, or the strokes of its stroke instruments, never both, so `group-lanes` needs no rule for ordering them. To print a pitched instrument and a stroke instrument together, use two groups. ADR 0011 stands; this answers the question it left open.
