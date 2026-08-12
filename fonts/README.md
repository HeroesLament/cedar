# Fonts

Baked signed distance field atlases for the `:text` visual.

The arrangement mirrors `shaders/`: a maintainer tool produces an artifact,
the artifact is committed, and **consumers of wx_mvu never run the tool**. A
`mix deps.get` yields working text with no Rust toolchain, no font file, and
no image decoder anywhere in the dependency graph.

```
fonts/dejavu/DejaVuSans.ttf  ->  tools/atlas  ->  priv/fonts/dejavu-sans.font
```

## Rebuilding

```sh
mix wx_mvu.fonts.build          # rebake from fonts/fonts.exs
mix wx_mvu.fonts.build --check  # fail if the committed artifact has drifted
```

The `--check` form belongs in CI. A committed artifact nobody verifies is a
committed artifact that is quietly wrong.

## What is in the `.font` file

One compressed Erlang term holding the metrics *and* the atlas bytes: glyph
rectangles, per-glyph placement relative to the baseline, kerning pairs, and a
single-channel image. The 260 KB raw atlas compresses to about 25 KB.

A single term rather than the tool's natural JSON-plus-raw-pixels because the
alternative costs the runtime a JSON decoder and an image decoder, and neither
is worth acquiring to read data this project generated itself.
`:erlang.term_to_binary/2` is in OTP, understands binaries natively, and is
faster than either.

## Why a distance field

A bitmap atlas is sharp at exactly one size; everything else is a blur or a
staircase, and a viewport with a zoom control visits every size there is. A
distance field stores how far each texel is from the glyph outline, so the
edge can be reconstructed at any scale from one texture. `WxMVU.Font.px_range/2`
computes what the shader needs to know about the current size, and
`sdf_coverage` in `wx-mvu-shader-core` turns a sample into coverage.

## Adding a font

1. Put the file under `fonts/<family>/`, with its licence beside it.
2. Add an entry to `fonts/fonts.exs`.
3. `mix wx_mvu.fonts.build`.
4. Commit both the source font and `priv/fonts/<name>.font`.

Two constraints the manifest enforces, both found the hard way:

- **`padding` must be at least `range`.** The field extends `range` pixels
  past each glyph's ink. With less padding it is clipped by the neighbouring
  cell, and the outermost antialiased pixels sample another glyph's field.
- **The atlas must be wide enough.** The packer is a simple shelf and fails
  loudly rather than silently dropping glyphs; raise `width` or lower `size`.

`size` is the resolution the outlines are rasterized at, not a display size.
48px is enough detail that a 200pt title still has clean curves.

## Licensing

DejaVu Sans is Bitstream Vera derived: freely redistributable, with no
reserved font name clause. Its licence is at `fonts/dejavu/LICENSE` and ships
in the Hex package alongside the atlas. A font under the SIL Open Font License
would work equally well technically but carries obligations worth reading
before adding one.
