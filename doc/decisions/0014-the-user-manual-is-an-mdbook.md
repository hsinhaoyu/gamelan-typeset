# 0014 The user manual is an mdBook, written with the code

Status: accepted (2026-11-20)

Context: notasi needs a user manual for musicians, separate from the README (for developers) and `doc/design/` (the specification). A manual written at the end goes stale or never gets written, and its examples drift from the notation. Typst, which already draws the figures, was considered for the manual, but its HTML export is still experimental (Typst 0.15), and a manual that only exists as a PDF is hard to read on a phone.

Decision: The manual is an mdBook in `doc/manual/`, written in Markdown, in the tone set by `doc/manual/STYLE.md`. It describes only implemented behaviour, and is updated in the same PR as any change a user can see. Its examples are `.gml` files that `make check` reads with the reader. CI builds it on every PR, and deploys it to GitHub Pages on every push to `main`, so the published manual matches the latest release.

Consequences: Writing the manual is part of each milestone, not a separate task. mdBook (a single binary) is a documentation-only dependency; the code does not depend on it. The manual has no score figures until the Typst backend exists; then the build will need a step that renders examples to SVG. Revisit Typst for the manual if its HTML export becomes stable.
