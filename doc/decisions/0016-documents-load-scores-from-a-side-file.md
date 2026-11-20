# 0016 Typst documents load scores from a side file

Status: proposed

Context: Besides standalone figures, notasi should typeset scores inside documents and textbooks written in Typst, as lilypond-book does for LaTeX. Typst cannot run other programs while compiling, and its WebAssembly plugins cannot currently host Guile compiled with Hoot (which needs WasmGC). lilypond-book's approach, rewriting the source into a second file to compile, would break Typst's live preview and leave the user editing one file and compiling another.

Decision: The user's `.typ` file is never rewritten. Scores are written in ` ```nts ` blocks or named with `notasi.file`. The `notasi` command finds them by querying the document with Typst (`typst eval --in`), lays them out in Guile, and writes their figures, or their errors, to a side file (`NAME.notasi.json`) keyed by snippet text. A Typst package loads that file and draws each score with the template of 05; a score missing from the side file is drawn as a placeholder, and an error as a message in the document. Captions, numbering and references are Typst's own, so the template returns plain content rather than a `figure`. Design in `doc/design/06-documents.md`.

Consequences: Documents always compile, and previews keep working with `notasi watch` running beside them. notasi never parses Typst. Guile still makes every musical decision (ADR 0005), and the figure JSON is reused unchanged inside a versioned side file: ADR 0006 still holds for each figure, and the manifest's own `version` covers the wrapper. Users must install Guile and run notasi, and must load the side file themselves, because a Typst package cannot read the project's files. Layout does not know the text width, so system breaks are set by hand for now.
