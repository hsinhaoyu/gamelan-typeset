# gamelan-typesetting

Tools for notating and visualizing Balinese gamelan music, written in GNU Guile 3.0.

## Layout

- `gamelan/piece.scm`: records for a piece (instruments, notes, parts)
- `gamelan/reader.scm`: parses textual notation into a piece
- `gamelan/layout.scm`: lays out scores
- `gamelan/typst.scm`: renders to Typst
- `gamelan/analysis.scm`: analysis tools
- `tests/`: SRFI-64 test suites
- `examples/`: example pieces
- `doc/notation.md`: notation reference
- `doc/design/`: design documents (the current design)
- `doc/decisions/`: decision log (why the design is the way it is)

## Running tests

    make check

Requires Guile 3.0. Run code from the repo root with `guile -L .`.
