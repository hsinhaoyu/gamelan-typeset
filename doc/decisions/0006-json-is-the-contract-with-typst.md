# 0006 The JSON file is the contract with Typst

Status: accepted (2026-11-19)

Context: Guile and Typst are separate programs and need a stable interface between them.

Decision: Layout output is a JSON figure description, specified in `doc/design/05-typst-backend.md` and covered by golden tests. The format has a `version` field.

Consequences: Any change to the format increments `version` and updates the template and golden tests in the same PR. The template can be developed against hand-written JSON.
