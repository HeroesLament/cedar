defmodule Cedar.FontTest do
  @moduledoc """
  Font loading and text layout, without a GL context.

  Layout is where text goes wrong in ways that still render: a sign flip puts
  the line above the origin instead of below it, a missing scale makes 8pt text
  48px tall, an off-by-one in the atlas rectangle samples a neighbouring
  glyph's edge. All of those draw *something*, so none of them are caught by
  "does it appear". They are caught here, on the numbers.
  """

  use ExUnit.Case, async: true

  alias Cedar.Font

  setup_all do
    %{font: Font.load(:dejavu_sans)}
  end

  defp close?(a, b, tolerance \\ 1.0e-4), do: abs(a - b) <= tolerance

  describe "load/1" do
    test "the bundled font is there", %{font: font} do
      assert font.name == "dejavu-sans"
      assert font.atlas_width > 0
      assert font.atlas_height > 0
    end

    test "the atlas is exactly one byte per texel", %{font: font} do
      # Anything else and the texture upload reads off the end, or silently
      # renders the atlas sheared.
      assert byte_size(font.atlas) == font.atlas_width * font.atlas_height
    end

    test "it covers printable ASCII", %{font: font} do
      missing = Enum.reject(32..126, &Map.has_key?(font.glyphs, &1))

      assert missing == []
    end

    test "the vertical metrics have the signs they should", %{font: font} do
      assert font.ascent > 0
      assert font.descent < 0
      assert font.line_height > font.ascent
    end

    test "it lists itself among the bundled fonts" do
      assert :dejavu_sans in Font.names()
    end

    test "an unknown font says what is available" do
      assert_raise ArgumentError, ~r/unknown font :comic_sans.*dejavu_sans/s, fn ->
        Font.load(:comic_sans)
      end
    end
  end

  describe "layout/3" do
    test "an empty string lays out to nothing", %{font: font} do
      assert %{quads: [], width: +0.0, lines: 1} = Font.layout(font, "")
    end

    test "one glyph is one quad", %{font: font} do
      assert %{quads: [_]} = Font.layout(font, "A", size: 16.0)
    end

    test "a space advances the pen but emits no quad", %{font: font} do
      # A space has an advance and no ink. Emitting its quad would cost six
      # vertices per space to draw a transparent rectangle.
      spaced = Font.layout(font, "A A", size: 16.0)
      tight = Font.layout(font, "AA", size: 16.0)

      assert length(spaced.quads) == 2
      assert spaced.width > tight.width
    end

    test "size scales the geometry linearly", %{font: font} do
      small = Font.layout(font, "Hg", size: 10.0)
      large = Font.layout(font, "Hg", size: 20.0)

      assert close?(large.width, small.width * 2.0, 1.0e-3)
      assert close?(large.height, small.height * 2.0, 1.0e-3)
    end

    test "size does not move the texture coordinates", %{font: font} do
      # The whole premise of a distance field atlas: the same texels serve
      # every size.
      [small] = Font.layout(font, "A", size: 8.0).quads
      [large] = Font.layout(font, "A", size: 96.0).quads

      assert close?(small.u0, large.u0)
      assert close?(small.v1, large.v1)
    end

    test "the origin is the top-left of the first line", %{font: font} do
      # y grows downwards, so a cap-height glyph's top edge sits below the
      # origin - the gap is the font's internal leading, not a sign error.
      [quad] = Font.layout(font, "H", size: 20.0, origin: {5.0, 7.0}).quads

      assert quad.y0 > 7.0
      assert quad.y0 < 7.0 + 20.0
      assert close?(quad.x0, 5.0, 20.0)
    end

    test "the quad extends beyond the ink, by design", %{font: font} do
      # The distance field reaches `range` pixels past the outline, and the
      # quad has to include that or the antialiased edge is clipped square.
      # So the first glyph's quad starts slightly *left* of the pen.
      [quad] = Font.layout(font, "H", size: 20.0, origin: {5.0, 0.0}).quads

      assert quad.x0 < 5.0
      assert quad.x0 > 5.0 - 20.0
    end

    test "moving the origin translates every quad", %{font: font} do
      [a] = Font.layout(font, "H", size: 20.0, origin: {0.0, 0.0}).quads
      [b] = Font.layout(font, "H", size: 20.0, origin: {100.0, 50.0}).quads

      assert close?(b.x0 - a.x0, 100.0)
      assert close?(b.y0 - a.y0, 50.0)
    end

    test "a descender reaches below a baseline glyph", %{font: font} do
      [x] = Font.layout(font, "x", size: 40.0).quads
      [p] = Font.layout(font, "p", size: 40.0).quads

      assert p.y1 > x.y1
    end

    test "text advances left to right", %{font: font} do
      [first, second] = Font.layout(font, "HH", size: 20.0).quads

      assert second.x0 > first.x0
    end

    test "newlines start a new line, downwards", %{font: font} do
      [first, second] = Font.layout(font, "H\nH", size: 20.0).quads

      assert close?(second.x0, first.x0)
      assert second.y0 > first.y0
    end

    test "height counts lines, not ink", %{font: font} do
      one = Font.layout(font, "H", size: 20.0)
      three = Font.layout(font, "H\nH\nH", size: 20.0)

      assert three.lines == 3
      assert close?(three.height, one.height * 3.0)
    end

    test "width is the widest line", %{font: font} do
      wide = Font.layout(font, "MMMMM", size: 20.0)
      mixed = Font.layout(font, "H\nMMMMM\nH", size: 20.0)

      assert close?(mixed.width, wide.width)
    end

    test "kerning tightens a pair that should kern", %{font: font} do
      kerned = Font.layout(font, "AV", size: 40.0, kerning: true)
      unkerned = Font.layout(font, "AV", size: 40.0, kerning: false)

      assert kerned.width < unkerned.width
    end

    test "kerning does not apply across a line break", %{font: font} do
      # The pen resets; a kerning pair spanning the newline would pull the
      # second line's first glyph sideways for no reason.
      [_, second] = Font.layout(font, "A\nV", size: 40.0).quads
      [only] = Font.layout(font, "V", size: 40.0).quads

      assert close?(second.x0, only.x0)
    end

    test "a character with no glyph is skipped, not substituted", %{font: font} do
      # A missing degree sign should not take a robot's status readout down
      # with it, and a tofu box is worse than nothing in a 12px label.
      with_missing = Font.layout(font, "A\u{1F600}A", size: 16.0)
      without = Font.layout(font, "AA", size: 16.0)

      assert length(with_missing.quads) == 2
      assert close?(with_missing.width, without.width)
    end

    test "texture coordinates stay inside the atlas", %{font: font} do
      quads = Font.layout(font, Enum.map_join(32..126, &<<&1>>), size: 24.0).quads

      assert Enum.all?(quads, fn q ->
               q.u0 >= 0.0 and q.v0 >= 0.0 and q.u1 <= 1.0 and q.v1 <= 1.0
             end)
    end

    test "every quad has positive extent", %{font: font} do
      quads = Font.layout(font, "The quick brown fox, 0123456789!", size: 18.0).quads

      assert Enum.all?(quads, &(&1.x1 > &1.x0 and &1.y1 > &1.y0))
    end

    test "line_height overrides the font's own", %{font: font} do
      default = Font.layout(font, "H\nH", size: 20.0)
      forced = Font.layout(font, "H\nH", size: 20.0, line_height: 100.0)

      assert close?(forced.height, 200.0)
      assert forced.height > default.height
    end
  end

  describe "measure/3" do
    test "it agrees with layout", %{font: font} do
      %{width: w, height: h} = Font.layout(font, "Joint 3", size: 14.0)

      assert Font.measure(font, "Joint 3", size: 14.0) == {w, h}
    end

    test "a longer string is wider", %{font: font} do
      {short, _} = Font.measure(font, "12", size: 14.0)
      {long, _} = Font.measure(font, "123456", size: 14.0)

      assert long > short
    end
  end

  describe "px_range/2" do
    test "it scales with the drawn size", %{font: font} do
      assert Font.px_range(font, font.size) == 2.0 * font.range
      assert close?(Font.px_range(font, font.size / 2), font.range)
    end

    test "small text gets a softer edge than large text", %{font: font} do
      # Which is the correct direction: at 8px a glyph stem is barely a pixel
      # wide, and a hard threshold would alias it into fragments.
      assert Font.px_range(font, 8.0) < Font.px_range(font, 64.0)
    end
  end

  describe "vertices/1" do
    test "six vertices of four floats per quad", %{font: font} do
      quads = Font.layout(font, "Hi", size: 16.0).quads

      assert byte_size(Font.vertices(quads)) == length(quads) * 6 * 16
    end

    test "no quads is no bytes" do
      assert Font.vertices([]) == <<>>
    end

    test "the two triangles share a diagonal, not a random pair", %{font: font} do
      [quad] = Font.layout(font, "H", size: 16.0).quads

      corners =
        for <<x::float-32-native, y::float-32-native, _u::float-32-native,
              _v::float-32-native <- Font.vertices([quad])>> do
          {x, y}
        end

      # Four distinct corners over six vertices: exactly two are repeated,
      # and those two are the shared diagonal.
      assert length(Enum.uniq(corners)) == 4

      repeated =
        corners
        |> Enum.frequencies()
        |> Enum.filter(fn {_corner, n} -> n == 2 end)
        |> Enum.map(&elem(&1, 0))

      assert length(repeated) == 2

      [{ax, ay}, {bx, by}] = repeated
      assert ax != bx and ay != by, "the repeated corners are not diagonal"
    end
  end
end
