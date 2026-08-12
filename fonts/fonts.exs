# Font manifest for `mix wx_mvu.fonts.build`.
#
# The same arrangement as shaders/shaders.exs, for the same reason: the baked
# artifact is committed, the tool that bakes it is a maintainer dependency, and
# this file is the record of exactly which parameters produced what is in
# priv/fonts.
#
# ## The parameters that matter
#
# `size` is the resolution the glyph outlines are rasterized at, not a size
# anything is displayed at — a distance field is resolution-independent by
# construction, and 48px is enough detail that a 200pt title still has clean
# curves.
#
# `range` is the distance, in baked pixels, that the field's full 0..1 range
# spans. Too small and the antialiasing has nothing to work with at small
# sizes; too large and thin stems lose contrast because their interior never
# reaches saturation. 6 at a 48px bake is a well-trodden ratio.
#
# `padding` must be at least `range`, or a glyph's field is clipped by its
# neighbour's cell and the outermost antialiased pixels come out wrong.

%{
  atlas_tool: "tools/atlas",

  fonts: [
    %{
      name: "dejavu-sans",
      # DejaVu is Bitstream Vera derived: freely redistributable, no reserved
      # font name clause, and packaged nearly everywhere. See
      # fonts/dejavu/LICENSE, which ships in the package alongside the atlas.
      source: "fonts/dejavu/DejaVuSans.ttf",
      license: "fonts/dejavu/LICENSE",
      size: 48,
      range: 6,
      padding: 6,
      width: 1024,
      # Beyond printable ASCII. Symbols an instrument readout actually needs -
      # degrees, tolerances, micro, ohms, arrows, comparisons - and the
      # Unicode chess pieces, which examples/chess.exs draws as text. Twelve
      # glyphs is a small price for a demo that needs no assets of its own,
      # and they are the clearest proof that :text is drawing real glyph
      # outlines rather than a bitmap font's ASCII table.
      extra: "°±×÷µΩ→←↑↓•√≈≠≤≥♔♕♖♗♘♙♚♛♜♝♞♟"
    }
  ]
}
