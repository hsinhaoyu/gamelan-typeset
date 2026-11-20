# 0021 pastel1 is the default palette

Status: accepted (2026-11-20)

Context: ADR 0017 made ColorBrewer's `dark2` the default palette for colouring notes by pitch, because white text stays readable on most of its colours. Since then note names are hidden by default (ADR 0019) and notes fill their cells (ADR 0020), so a score is mostly coloured blocks, and strong colours made it look heavy. Comparing the softer ColorBrewer palettes on a real example, `pastel1` was preferred.

Decision: The default palette is `pastel1` (nine colours). `dark2` and the other palettes stay available through `make-style #:palette`. To match, stroke boxes are a lighter grey, `#cccccc` instead of ADR 0019's `#999999`.

Consequences: Default figures are lighter; every pitch colour takes near-black text, so names, where shown, are dark. A scale of up to nine degrees gets a different colour for each. The pale colours are closer to each other and to white, so pitches are a little harder to tell apart at a glance than with `dark2`; a piece that needs more contrast can choose another palette. Stroke boxes, still grey, now sit with the pastels instead of being the darkest notes in the figure. This replaces only the default palette named in ADR 0017 and the stroke grey named in ADR 0019; the rest of both stands.

Supersedes: 0017 (only the default palette), 0019 (only the stroke grey)
