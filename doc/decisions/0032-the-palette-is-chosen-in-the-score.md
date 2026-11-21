# 0032 The palette is chosen in the score

Status: accepted (2026-11-21)

Context: Colours are chosen by a style built in Guile with `make-style` (ADRs 0017, 0021), so a piece can't choose its own colours.

Decision: A score chooses its colours with `:scheme`, `:palette` (a ColorBrewer name or a list of `"#rrggbb"`) and `:colors` (colours for particular degrees), on the score or a group; and its sizes with `:font-size`, `:cell-width` and `:cell-height`. The notation chooses; Guile still works out the values and Typst only draws them (ADR 0005). The default stays `by-degree` with `pastel1`, and strokes stay grey.

Consequences: Where ADRs 0017 and 0021 say the scheme and palette are chosen through the style given to layout, read the score's options. A score's colours and sizes are checked by the reader.
