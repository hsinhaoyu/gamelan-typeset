# gamelan-typesetting

Tools for notating and visualizing Balinese gamelan music, written in GNU Guile 3.0.

## Layout

- `gamelan/model.scm`: core data model
- `gamelan/reader.scm`: parses textual notation into the model
- `gamelan/layout.scm`: lays out scores
- `gamelan/typst.scm`: renders to Typst
- `gamelan/analysis.scm`: analysis tools
- `tests/`: SRFI-64 test suites
- `examples/`: example pieces
- `doc/notation.md`: notation reference

## Running tests

    make check

Requires Guile 3.0. Run code from the repo root with `guile -L .`.
