# notasi

Tools for notating and visualizing Balinese gamelan music, written in GNU Guile 3.0.

## Layout

- `notasi/piece.scm`: records for a piece (instruments, notes, parts)
- `notasi/reader.scm`: parses textual notation into a piece
- `notasi/layout.scm`: lays out scores
- `notasi/typst.scm`: renders to Typst
- `notasi/analysis.scm`: analysis tools
- `tests/`: SRFI-64 test suites
- `examples/`: example pieces
- `templates/`: shared scales, stroke sets and instruments, loaded with `(use NAME)`
- `doc/notation.md`: notation reference
- `doc/design/`: design documents (the current design)
- `doc/decisions/`: decision log (why the design is the way it is)

## Running tests

    make check

Requires Guile 3.0. Run code from the repo root with `guile -L .`.
