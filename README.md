# notasi

Tools for notating and visualizing Balinese gamelan music, written in GNU Guile 3.0.

## Layout

- `notasi/piece.scm`: records for a piece (instruments, notes, parts)
- `notasi/reader.scm`: parses textual notation into a piece
- `notasi/layout.scm`: lays out scores
- `notasi/json.scm`: writes JSON (the figure files Typst reads)
- `notasi/style.scm`: how notes look: palettes and colour schemes
- `notasi/typst.scm`: the Guile side of the Typst backend (so far: writes figure files)
- `tests/`: SRFI-64 test suites
- `examples/`: example pieces
- `templates/`: shared scales, stroke sets and instruments, loaded with `(use NAME)`
- `doc/design/01-notation.md`: the notation language
- `doc/manual/`: the user manual (mdBook)
- `doc/design/`: design documents (the current design)
- `doc/decisions/`: decision log (why the design is the way it is)

## User manual

The manual for musicians is at <https://hsinhaoyu.github.io/notasi/>. Its
source is in `doc/manual/`; build it locally with `make manual`, or preview
it with `make manual-serve`. Both need [mdBook](https://rust-lang.github.io/mdBook/).

## Running tests

    make check

`make check` includes golden tests: each piece in `examples/` is laid
out and compared with its saved figure in `tests/golden/`. When you
change the output on purpose, run `make golden` to rewrite the saved
figures, and review the diff.

Requires Guile 3.0. Run code from the repo root with `guile -L .`.
