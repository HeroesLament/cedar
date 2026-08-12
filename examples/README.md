# Examples

Run any of these from the repository root:

```sh
mix run examples/chess.exs
```

They are scripts rather than a separate mix project on purpose: an example
that needs its own build step is an example nobody runs.

## chess.exs

A board with pieces you can push around by clicking. No rules, no opponent —
what it demonstrates is that a complete interactive graphical application can
be a pure function from a model to a declaration, with no GLSL, no buffers and
no rendering code.

The whole board is one `:layers` visual: an 8x8 `:image` for the squares, and
`:text` twice for the pieces, once per colour, using the Unicode chess glyphs
from the bundled DejaVu atlas.

Three things are worth reading it for.

**The selection is in the square texture.** There is no highlight layer.
"This square is selected" is a property of the square, so it is a value in the
8x8 field, and the colormap has four stops instead of two. Selecting a piece
uploads 64 bytes.

**Clicking draws nothing.** `handle_event/2` updates a map and returns. The
board redraws because `view/1` is a function of that map — the same reason a
label updates when you change the model behind it.

**Nothing in the file mentions the GPU.** No shader, no vertex buffer, no
texture, no draw call. `mix run examples/chess.exs` needs no Rust toolchain and
no font file, because the shaders and the atlas were compiled ahead of time and
are committed.

Read the `view/1` function first. It is the entire renderer.
