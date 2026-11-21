# 0031 Printing belongs to scores

Status: accepted (2026-11-21)

Context: In v1 printing is decided by the top-level `group` form, by settings in the music (`show-names` on instruments, `steps-per-system` on the piece), and by a style given from Guile. A part can't be written without being printed, the same music can't be printed two ways, and Tenzer's layout (names only, one row per part, sung lines) can't be asked for.

Decision: A `(score NAME :key value ... (group LABEL :key value ... PART ...) ...)` form says how the music is printed: which parts, in which groups, with which options. A file may have several; a part in no group of a score is not printed in it. Score options set the defaults for its groups, and group options override them. Groups exist only inside scores, and the rule of ADR 0011 applies within each score. A file without a score gets a default one, every part in its own group; `notasi render --score NAME` chooses one, and the first is the default. Note names are a score option, `:note-names`, off by default for strokes too. `steps-per-system` becomes `:system-length`, and the planned `(text STRING)` form is dropped: a score has a `:caption`, and Typst documents (06) do the rest.

Consequences: The music says only what sounds. Where ADR 0019 says names are set per instrument with `(show-names yes)`, read the score option `:note-names`; its square notes and `text: null` stand. Gong groups now ask for names explicitly. Layout takes a score as well as a piece, and the figure and JSON change accordingly (04, 05).
