# 0001 Notation is s-expressions

Status: accepted (2026-11-19)

Context: The reader needs a tokeniser and parser. Writing one is work, and a custom syntax is harder to extend and to get right.

Decision: `.gml` files are s-expressions, read with Guile's built-in `read`. A friendlier surface syntax can be added later as a second front end that produces the same model.

Consequences: No custom tokeniser is needed. Notation must fit s-expression syntax (symbols, numbers, lists). Any later surface syntax must not change the model.
