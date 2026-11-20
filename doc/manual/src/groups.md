# Groups

Interlocking parts are easiest to read together. A **group** draws
several parts in one block, sharing the same rows, so you can see how
they fit:

```scheme
{{#include examples/kotekan-group.nts}}
```

`(group "Reyong" polos sangsih)` puts polos and sangsih together under
the label *Reyong*. The label is in double quotes. After the parts, you
can add a subtitle: `(subtitle "polos + sangsih")`.

## Parts without a group

Every part not in a `group` gets a block of its own, labelled with the
part's name. In the example the gong is labelled *gong*.

## The order of blocks

Blocks follow the order you wrote the parts in. A group sits where its
first part is, wherever the `group` line itself is. In the example,
*Reyong* comes first, because polos is the first part in the file, and
*gong* comes second.

## The rules

- A part can be in only one group.
- All the pitched parts in a group play the **same instrument**, so
  that their rows line up. To compare the ugal and the reyong, give
  each its own group. Gongs, drums and the kempli can share a group
  with each other, or with one pitched instrument.
