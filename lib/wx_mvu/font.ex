defmodule WxMVU.Font do
  @moduledoc """
  A baked signed distance field font: its metrics, its atlas, and text layout.

      font = WxMVU.Font.load(:dejavu_sans)
      %{quads: quads, width: w} = WxMVU.Font.layout(font, "Joint 3: 47.2°", size: 14.0)

  Loading reads one file from `priv/fonts`. There is no font parsing here and
  no rasterizer — `mix wx_mvu.fonts.build` did that ahead of time, the result
  is committed, and the runtime cost of a font is a `File.read!` and a term
  decode.

  ## Coordinates

  Layout is in **pixels with the origin at the top left and y increasing
  downwards**, which is the coordinate system every font metric in existence
  assumes and the one `:text`'s vertex shader converts from. A quad's `y0` is
  its top edge.

  The pen starts at the origin on the *baseline*, so glyph tops are negative
  before a position is applied. `layout/3` takes an `:origin` to shift that,
  and defaults it to `{0.0, ascent}` — placing the first line's ascender at
  y = 0, which is what "draw this text at (x, y)" almost always means.

  ## Sizes

  A distance field is resolution-independent, so `:size` is free: the same
  atlas serves 8px labels and 200px titles. What changes with size is the
  antialiasing width, which the visual derives and hands the shader as
  `px_range` — see `px_range/2`.
  """

  alias WxMVU.Font.Glyph

  defmodule Glyph do
    @moduledoc """
    One glyph's placement.

    `x`, `y`, `w`, `h` locate it in the atlas, *including* the padding the
    distance field extends into — a quad cropped to the ink would clip its own
    antialiased edge. `left` and `top` position that same padded region
    relative to the pen on the baseline, in baked pixels, y down.
    """

    @type t :: %__MODULE__{
            x: non_neg_integer(),
            y: non_neg_integer(),
            w: non_neg_integer(),
            h: non_neg_integer(),
            left: float(),
            top: float(),
            advance: float()
          }

    defstruct [:x, :y, :w, :h, :left, :top, :advance]
  end

  @type t :: %__MODULE__{
          name: String.t(),
          size: float(),
          range: float(),
          atlas: binary(),
          atlas_width: pos_integer(),
          atlas_height: pos_integer(),
          ascent: float(),
          descent: float(),
          line_height: float(),
          glyphs: %{integer() => Glyph.t()},
          kerning: %{{integer(), integer()} => float()}
        }

  defstruct [
    :name,
    :size,
    :range,
    :atlas,
    :atlas_width,
    :atlas_height,
    :ascent,
    :descent,
    :line_height,
    :glyphs,
    :kerning
  ]

  @type quad :: %{
          x0: float(),
          y0: float(),
          x1: float(),
          y1: float(),
          u0: float(),
          v0: float(),
          u1: float(),
          v1: float()
        }

  @doc """
  Loads a baked font from `priv/fonts`.

  Takes an atom naming a bundled font (`:dejavu_sans`) or a path to a `.font`
  file of your own.
  """
  @spec load(atom() | Path.t()) :: t()
  def load(name) when is_atom(name) do
    file = name |> Atom.to_string() |> String.replace("_", "-")
    path = Path.join([:code.priv_dir(:wx_mvu), "fonts", "#{file}.font"])

    unless File.exists?(path) do
      raise ArgumentError,
            "unknown font #{inspect(name)}. Bundled fonts: #{inspect(names())}"
    end

    load(path)
  end

  def load(path) when is_binary(path) do
    term = path |> File.read!() |> :erlang.binary_to_term([:safe])

    unless is_map(term) and term[:version] == 1 do
      raise ArgumentError,
            "#{path} is not a wx_mvu font, or was baked by a different version " <>
              "of mix wx_mvu.fonts.build"
    end

    %__MODULE__{
      name: term.name,
      size: term.size,
      range: term.range,
      atlas: term.atlas,
      atlas_width: term.atlas_width,
      atlas_height: term.atlas_height,
      ascent: term.ascent,
      descent: term.descent,
      line_height: term.line_height,
      glyphs: Map.new(term.glyphs, fn {cp, g} -> {cp, struct!(Glyph, g)} end),
      kerning: term.kerning
    }
  end

  @doc "Names of the fonts bundled with wx_mvu."
  @spec names() :: [atom()]
  def names do
    [:code.priv_dir(:wx_mvu), "fonts", "*.font"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.map(fn path ->
      path |> Path.basename(".font") |> String.replace("-", "_") |> String.to_atom()
    end)
  end

  @doc """
  Screen pixels spanned by the atlas's full distance range, at a given size.

  This is what makes one atlas serve every size: the field is stored in baked
  pixels, and the shader needs it in screen pixels to know how wide to make the
  antialiased edge.
  """
  @spec px_range(t(), number()) :: float()
  def px_range(%__MODULE__{} = font, size) do
    2.0 * font.range * (size / font.size)
  end

  @doc """
  Lays a string out into textured quads.

  ## Options

    * `:size` - em size in pixels, default the font's baked size
    * `:origin` - `{x, y}` for the top-left of the first line, default
      `{0.0, 0.0}`
    * `:line_height` - override, in pixels at the requested size
    * `:kerning` - default `true`

  Returns `%{quads: [...], width: w, height: h, lines: n}`. `width` is the
  widest line's advance, which is what a layout engine wants — not the ink
  extent, which would jitter as the last character changed.

  Characters with no glyph in the atlas are skipped rather than raising or
  substituting a box. A missing glyph is a font coverage problem, and dropping
  a degree sign should not take a robot's status readout down with it.
  """
  @spec layout(t(), String.t(), keyword()) :: %{
          quads: [quad()],
          width: float(),
          height: float(),
          lines: pos_integer()
        }
  def layout(%__MODULE__{} = font, text, opts \\ []) when is_binary(text) do
    size = Keyword.get(opts, :size, font.size) * 1.0
    scale = size / font.size
    {origin_x, origin_y} = Keyword.get(opts, :origin, {0.0, 0.0})
    line_height = Keyword.get(opts, :line_height, font.line_height * scale) * 1.0
    kern? = Keyword.get(opts, :kerning, true)

    lines = String.split(text, "\n")

    # The pen sits on the baseline; the caller's origin is the top of the line.
    baseline = origin_y + font.ascent * scale

    {quads, widths} =
      lines
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {line, index}, widths ->
        {line_quads, width} =
          layout_line(font, line, scale, origin_x, baseline + index * line_height, kern?)

        {line_quads, [width | widths]}
      end)
      |> then(fn {quads, widths} -> {List.flatten(quads), Enum.reverse(widths)} end)

    %{
      quads: quads,
      width: Enum.max(widths, fn -> 0.0 end),
      height: length(lines) * line_height,
      lines: length(lines)
    }
  end

  @doc """
  The size a string would occupy, without building its quads.

  For sizing a control around a label, where the geometry is never drawn.
  """
  @spec measure(t(), String.t(), keyword()) :: {float(), float()}
  def measure(%__MODULE__{} = font, text, opts \\ []) do
    %{width: width, height: height} = layout(font, text, opts)
    {width, height}
  end

  # ==========================================================================

  defp layout_line(font, line, scale, origin_x, baseline, kern?) do
    {quads, {pen, _previous}} =
      line
      |> String.to_charlist()
      |> Enum.flat_map_reduce({origin_x, nil}, fn codepoint, {pen, previous} ->
        case Map.fetch(font.glyphs, codepoint) do
          :error ->
            # Skipped entirely, including for kerning: the pair that matters
            # is the one the reader sees, so a dropped character must not
            # break the kern between the glyphs either side of it.
            {[], {pen, previous}}

          {:ok, glyph} ->
            kern = if kern?, do: kerning(font, previous, codepoint) * scale, else: 0.0
            pen = pen + kern

            {[quad(font, glyph, pen, baseline, scale)], {pen + glyph.advance * scale, codepoint}}
        end
      end)

    {Enum.reject(quads, &empty?/1), pen - origin_x}
  end

  defp kerning(_font, nil, _codepoint), do: 0.0

  defp kerning(font, previous, codepoint) do
    Map.get(font.kerning, {previous, codepoint}, 0.0)
  end

  defp quad(font, glyph, pen, baseline, scale) do
    x0 = pen + glyph.left * scale
    y0 = baseline + glyph.top * scale

    aw = font.atlas_width * 1.0
    ah = font.atlas_height * 1.0

    %{
      x0: x0,
      y0: y0,
      x1: x0 + glyph.w * scale,
      y1: y0 + glyph.h * scale,
      # v runs the same way as the atlas rows, which are uploaded top row
      # first. No flip: the quad's top edge and the glyph's top row are both
      # the smaller coordinate.
      u0: glyph.x / aw,
      v0: glyph.y / ah,
      u1: (glyph.x + glyph.w) / aw,
      v1: (glyph.y + glyph.h) / ah
    }
  end

  # A space is a real entry in the atlas - it has an advance - but no ink, so
  # emitting its quad would cost six vertices per space to draw nothing.
  defp empty?(quad), do: quad.x1 - quad.x0 <= 0.0 or quad.y1 - quad.y0 <= 0.0

  @doc """
  Packs laid-out quads into the vertex binary `:text` expects.

  Two triangles per quad, `[a_position: {:f32, 2}, a_texcoord: {:f32, 2}]`.
  Separate from `layout/3` so that layout stays testable as data rather than
  as bytes.
  """
  @spec vertices([quad()]) :: binary()
  def vertices(quads) do
    quads
    |> Enum.flat_map(fn q ->
      top_left = {q.x0, q.y0, q.u0, q.v0}
      top_right = {q.x1, q.y0, q.u1, q.v0}
      bottom_left = {q.x0, q.y1, q.u0, q.v1}
      bottom_right = {q.x1, q.y1, q.u1, q.v1}

      [top_left, bottom_left, bottom_right, top_left, bottom_right, top_right]
    end)
    |> Enum.map(fn {x, y, u, v} ->
      <<x::float-32-native, y::float-32-native, u::float-32-native, v::float-32-native>>
    end)
    |> IO.iodata_to_binary()
  end
end
