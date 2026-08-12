defmodule WxMVU.Visual.Text do
  @moduledoc """
  Text, from a signed distance field atlas.

      {:ensure_visual, :readout, :text, :root,
        text: "Joint 3: 47.2°",
        size: 14.0,
        origin: {12.0, 12.0},
        color: {0.9, 0.92, 0.95, 1.0}}

      WxMVU.Visual.send_data(:readout, {:text, "Joint 3: \#{angle}°"})

  One atlas serves every size, because the glyph is stored as a distance to its
  outline rather than as coverage — see `WxMVU.Font`. Nothing here parses a
  font or rasterizes anything; `mix wx_mvu.fonts.build` did that ahead of time
  and its output is committed.

  ## Options

    * `:font` - a bundled font atom or a path, default `:dejavu_sans`
    * `:text` - a string at `:origin`
    * `:runs` - `[{{x, y}, string}, ...]`, several strings at several places
    * `:size` - em size in pixels, default `16.0`
    * `:origin` - `{x, y}` of the text's top-left, default `{0.0, 0.0}`

  Positions and sizes are in **logical points**, the same units wx uses for
  widget geometry, not physical pixels. On a HiDPI display the two differ by
  the DPI scale, and using physical pixels would make a 14pt label render at
  7pt on a Retina panel and text laid out against a widget's coordinates land
  in the wrong place. The extra resolution is not thrown away - the glyphs are
  rasterized at the physical size, which is exactly what the distance field is
  for.
    * `:color` - `{r, g, b, a}`, default opaque white
    * `:line_height`, `:kerning` - passed through to `WxMVU.Font.layout/3`

  Colour is a uniform; the string and everything affecting layout is geometry.
  So fading a label out costs 32 bytes, while changing its text rebuilds a
  vertex buffer — which is the right way round, since the first happens per
  frame during an animation and the second happens when a value changes.

  `:runs` is one draw call for many strings, which is what a set of axis tick
  labels, a scoreboard or a board full of pieces actually is. Laying each one
  out as its own visual would mean a program, a texture and a vertex buffer
  per label.

  ## Data

      {:text, string}                    # replaces the string
      {:runs, [{{x, y}, string}, ...]}   # replaces every run
      :clear                             # draws nothing

  ## Blending

  Glyph edges are antialiased into the alpha channel, so this enables alpha
  blending while it draws. Text over an opaque background needs nothing else;
  text composited into a framebuffer you then blend again wants premultiplied
  alpha, which this deliberately does not do — see the shader's comment.
  """

  use WxMVU.Visual

  alias WxMVU.Font
  alias WxMVU.Renderer.GL

  defstruct [
    :program,
    :geometry,
    :texture,
    :font,
    :text,
    :runs,
    :size,
    :origin,
    :color,
    :line_height,
    :kerning,
    vertex_count: 0
  ]

  defmodule Shader do
    @moduledoc false

    use WxMVU.GLCanvas.Draw.Program,
      source: {:priv, :wx_mvu, "shaders/text"},
      blocks: [
        per_frame: [
          name: "TextUniforms",
          binding: 0,
          fields: [color: :vec4, viewport: :vec2, px_range: :f32]
        ]
      ],
      samplers: [u_atlas: 0],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  @layout [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]

  @impl true
  def init(_ctx, opts) do
    font = Font.load(Keyword.get(opts, :font, :dejavu_sans))

    with {:ok, program} <- Shader.load() do
      texture =
        Texture.new(font.atlas_width, font.atlas_height, format: :r8, filter: :linear)

      Texture.upload(texture, font.atlas)

      state = %__MODULE__{
        program: program,
        geometry: Geometry.new(<<>>, layout: @layout, mode: :triangles, usage: :dynamic),
        texture: texture,
        font: font,
        text: Keyword.get(opts, :text, ""),
        runs: Keyword.get(opts, :runs),
        size: Keyword.get(opts, :size, 16.0) * 1.0,
        origin: Keyword.get(opts, :origin, {0.0, 0.0}),
        color: Keyword.get(opts, :color, {1.0, 1.0, 1.0, 1.0}),
        line_height: Keyword.get(opts, :line_height),
        kerning: Keyword.get(opts, :kerning, true)
      }

      {:ok, rebuild(state)}
    end
  end

  @impl true
  def update(state, opts) do
    # Changing the font means a different atlas texture, which is not an
    # incremental update to anything.
    if Keyword.has_key?(opts, :font) and
         Font.load(opts[:font]).name != state.font.name do
      {:reinit, :font_changed}
    else
      updated = %{
        state
        | text: Keyword.get(opts, :text, state.text),
          runs: Keyword.get(opts, :runs, state.runs),
          size: Keyword.get(opts, :size, state.size) * 1.0,
          origin: Keyword.get(opts, :origin, state.origin),
          color: Keyword.get(opts, :color, state.color),
          line_height: Keyword.get(opts, :line_height, state.line_height),
          kerning: Keyword.get(opts, :kerning, state.kerning)
      }

      if layout_changed?(state, updated) do
        {:ok, rebuild(updated)}
      else
        {:ok, updated}
      end
    end
  end

  @impl true
  def handle_data(state, {:text, text}) when is_binary(text) do
    if text == state.text do
      {:ok, state}
    else
      {:ok, rebuild(%{state | text: text})}
    end
  end

  def handle_data(state, {:runs, runs}) when is_list(runs) do
    {:ok, rebuild(%{state | runs: runs})}
  end

  def handle_data(state, :clear), do: {:ok, rebuild(%{state | text: "", runs: nil})}

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, frame) do
    if state.vertex_count > 0 do
      {width, height} = frame.logical_size

      GL.enable(:blend)
      GL.blend_func(:alpha)

      state.program
      |> Program.bind()
      |> Program.set_block(:per_frame, %{
        color: state.color,
        viewport: {width * 1.0, height * 1.0},
        # The glyph covers size * dpi_scale *physical* pixels even though it
        # was positioned in logical ones, and the antialiasing width is a
        # physical-pixel quantity. Dropping the scale here is why text looks
        # soft on a Retina display in so many toolkits.
        px_range: Font.px_range(state.font, state.size * (frame.dpi_scale || 1.0))
      })

      Texture.bind(state.texture, Program.texture_unit(state.program, :u_atlas))

      Geometry.draw(state.geometry)

      # Restored rather than left on. A visual that changes global GL state and
      # walks away is a bug waiting for the first canvas that draws two things.
      GL.disable(:blend)
    end

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Geometry.delete(state.geometry)
    Texture.delete(state.texture)
    Program.delete(state.program)
    :ok
  end

  @doc """
  The laid-out size of the current string, in pixels.

  For a caller sizing something around a label without drawing it.
  """
  @spec measure(%__MODULE__{}) :: {float(), float()}
  def measure(%__MODULE__{} = state) do
    Font.measure(state.font, state.text, layout_opts(state))
  end

  # ==========================================================================

  defp rebuild(state) do
    quads =
      case state.runs do
        nil ->
          Font.layout(state.font, state.text, layout_opts(state)).quads

        runs ->
          # Every run is laid out against its own origin and the quads are
          # concatenated. They share one atlas, one program and one buffer, so
          # the cost of the hundredth label is its glyphs and nothing else.
          Enum.flat_map(runs, fn {origin, text} ->
            Font.layout(state.font, text, Keyword.put(layout_opts(state), :origin, origin)).quads
          end)
      end

    vertices = Font.vertices(quads)

    %{
      state
      | geometry: Geometry.update(state.geometry, vertices),
        vertex_count: length(quads) * 6
    }
  end

  defp layout_opts(state) do
    [size: state.size, origin: state.origin, kerning: state.kerning] ++
      if(state.line_height, do: [line_height: state.line_height], else: [])
  end

  defp layout_changed?(before, later) do
    Map.take(before, [:text, :runs, :size, :origin, :line_height, :kerning]) !=
      Map.take(later, [:text, :runs, :size, :origin, :line_height, :kerning])
  end
end
