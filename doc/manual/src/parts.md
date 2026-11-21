# Several parts on one instrument

Most parts are the only part on their instrument, and take its name:
`(part ugal …)` is the part `ugal`. Interlocking parts are different:
two players share the reyong, one playing polos and the other sangsih.
Give each part its own name with `:name`:

```scheme
{{#include examples/two-parts.nts}}
```

The reyong has two parts here, `polos` and `sangsih`. The gong has
only one, so it is simply `gong`.

## The rules

- When an instrument has more than one part, every part on it needs a
  `:name`.
- Every part has its own name. Two parts can't share one, even on
  different instruments.
- `:name` comes right after the instrument, before the music.

For now, each part is drawn on its own in the score, with its name on
the left. Drawing polos and sangsih together in one block is coming
later.

Next: sharing scales and instruments between pieces, with
[templates](templates.md).
