# 0026 Options are written :key value

Status: accepted (2026-11-21)

Context: v1 writes options as lists, `(steps-per-pulse 4)`, `(alias i)`, `(show-names yes)`. Each option is a list head the reader must tell apart from music, and a part's body cannot mix tokens with lists of options without reserving names. Iteration 2 adds many options (to patterns, colotomies and scores).

Decision: Optional settings are `:key value` pairs, in Common Lisp style: a symbol starting with `:` and a letter, followed by one value (a list if it has several items). Options come after a form's positional arguments and before its body, in any order, each key once; an unknown key is an error. The reader reads with Guile's `keywords` option off, so `:pickup` is an ordinary symbol, and recognises the leading colon. Durations also use a colon, but never at the start (`o3:1/4`).

Consequences: Options need no reserved list heads, and every form uses the same convention. Every form with options changes syntax (`piece`, degrees, strokes, groups), so v1 files must be rewritten.
