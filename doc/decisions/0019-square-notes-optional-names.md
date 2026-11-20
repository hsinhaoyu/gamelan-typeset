# 0019 Notes are square blocks; note names are optional

Status: accepted (2026-11-20)

Context: The first drawings from the Typst template (05) showed notes as rounded blocks with their name written inside, and strokes (gong, kempli, kendang) as their letter alone (ADR 0017). Reviewing them, the rounded corners looked wrong for a grid score, and names inside pitched notes add clutter that the lanes and colours already say; longer names ("neng") also don't fit a one-step note. Strokes are the opposite: their lane label is the only other clue to which stroke it is, and players read them as letters.

Decision: Notes are square blocks. Whether a note shows its name is set per instrument in the notation, with the option `(show-names yes)` after the instrument's notes; without it, names are hidden. A note whose name is hidden has `text: null` in the figure. A stroke is drawn as a grey box (`#999999`), with its name in it when its instrument shows names. A note cut across systems starts flush with the system's left edge, so it reads as continuing from before. The `gong-kebyar` template shows names on its stroke instruments.

Consequences: Figures are quieter: pitched notes are coloured blocks, strokes grey blocks with letters where the template asks for them. The notation, the instrument record (a new field), the reader (instrument options, with the same errors as other options), layout and the template all change; the golden figures are regenerated. This replaces ADR 0017's "strokes are drawn as their display character only, with no box" and 05's rounded blocks; the rest of 0017 (colour by pitch) stands. A style setting for names, or a `style` form in the notation, can still come later.

Supersedes: 0017 (only how strokes are drawn)
