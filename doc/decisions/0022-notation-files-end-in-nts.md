# 0022 Notation files end in .nts

Status: accepted (2026-11-21)

Context: Notation files have ended in `.gml` since the start (ADR 0001). `.gml` is already widely used for other formats (Geography Markup Language, Graph Modelling Language, GameMaker), so editors and file browsers may misidentify it, and it doesn't hint at notasi.

Decision: Notation files end in `.nts` (for "notasi"). Templates are found as `templates/NAME.nts`, `notasi render PIECE.nts` writes `PIECE.pdf`, and code blocks in Typst documents are tagged ` ```nts `. The reader doesn't look for `.gml` files: there were no users outside the repository, so there is nothing to stay compatible with. Where earlier ADRs say `.gml`, read `.nts`.

Consequences: Every example, template, manual file and test fixture was renamed in one change. A file given by path, as in `(use "file.gml")` or `notasi render old.gml`, still reads, because the reader never checks the extension of a path it is given; only template names and the default output name depend on it.

Supersedes: none (ADR 0001's decision, that notation is s-expressions, stands)
