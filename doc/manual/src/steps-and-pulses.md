# Steps and pulses

notasi counts time in **steps**. A step is the shortest moment in the
piece. Each note or rest takes one step, and a longer note holds over
several steps (see [Notes, rests and holds](notes-rests-and-holds.md)).

A **pulse** is one stroke of the kempli (or kajar): the steady beat
that everyone feels. You tell notasi how many steps fit in one pulse,
and how many steps go on each line of the score, inside the `piece`
line:

```scheme
{{#include examples/piece-settings.gml}}
```

## `steps-per-pulse`

How many steps fit in one kempli stroke. A kotekan, with four notes to
each stroke, needs 4. notasi uses this to number the pulses and to show
where each one falls.

If you leave it out, notasi uses **4**.

For a slow melody, such as a pokok with one note to each stroke, use 1:

```scheme
{{#include examples/one-step-per-pulse.gml}}
```

## `steps-per-system`

How many steps go on one line (system) of the score, so that, for
example, each line holds one gong cycle. In the first example, 32 steps
at 4 steps per pulse is 8 pulses on each line.

If you leave it out, the whole piece goes on one line.

## The rules

- Each setting is a pair of round brackets holding its name and a whole
  number above zero: `(steps-per-pulse 4)`. Words (`four`) and decimals
  (`4.0`) aren't allowed.
- Give each setting at most once. Their order doesn't matter.

The full rules are in the
[notation reference](https://github.com/hsinhaoyu/notasi/blob/dev/doc/design/01-notation.md).
