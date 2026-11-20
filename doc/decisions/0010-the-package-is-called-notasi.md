# 0010 The package is called notasi

Status: accepted (2026-11-20)

Context: Modules lived under `(gamelan ...)` in `gamelan/`. Gamelan is a whole musical tradition; this package only notates, draws and analyses pieces, so the name claimed far more than it does.

Decision: The package namespace is `notasi` (Indonesian for "notation"): modules are `(notasi piece)`, `(notasi reader)` and so on, in `notasi/`. Names derived from the package follow it: `typst/notasi.typ`, `scripts/notasi-render`, `scripts/notasi-analyse`, `&notasi-syntax-error`. The `.gml` file extension and the repository name are unchanged. Where earlier ADRs name `(gamelan ...)` modules, read `(notasi ...)`.

Consequences: "Gamelan" in code and docs now refers only to the music, never to this package.
