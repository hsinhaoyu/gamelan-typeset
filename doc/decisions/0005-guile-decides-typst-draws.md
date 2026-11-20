# 0005 Guile decides, Typst draws

Status: accepted (2026-11-19)

Context: Musical layout logic could live in Guile or in the Typst template. Splitting it between both makes behaviour hard to test and reason about.

Decision: All musical decisions (system breaks, lanes, colours, grouping) are made in Guile, in `(gamelan layout)`. The Typst template only draws what the JSON says.

Consequences: Layout behaviour is tested in Guile with golden JSON files. The template stays small and contains no musical logic. Changing what is drawn usually means changing layout, not the template.
