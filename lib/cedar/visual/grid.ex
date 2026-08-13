defmodule Cedar.Visual.Grid do
  @moduledoc """
  Analytic, antialiased gridlines.

      {:ensure_visual, :grid, :grid, :root,
        spacing: {0.25, 0.25},
        thickness: 1.0,
        line_color: {0.3, 0.3, 0.35, 1.0},
        background: {0.08, 0.08, 0.1, 1.0}}

  Lines are computed per-fragment from the distance to the nearest cell
  boundary rather than drawn as geometry, so they stay exactly one thickness
  wide at any zoom, antialias for free, and never need a mesh rebuilt when the
  viewport changes.

  Backs plot gridlines now and the CAD ground plane once there is a camera to
  put it under.

  ## Options

    * `:spacing` - `{x, y}` cell size in the `0.0..1.0` surface coordinate,
      default `{0.1, 0.1}`
    * `:thickness` - line width in pixels, default `1.0`
    * `:line_color` - `{r, g, b, a}`, default a mid grey
    * `:background` - `{r, g, b, a}` between the lines, default near-black

  A one-pixel line is the common case and renders correctly: gridlines land on
  cell boundaries, which typically fall on pixel boundaries, so the coverage is
  split half-and-half across the two neighbouring pixels rather than
  disappearing.
  """

  use Cedar.Visual

  defstruct [:program, :geometry, :spacing, :thickness, :line_color, :background]

  defmodule Shader do
    @moduledoc false

    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/grid"},
      blocks: [
        per_frame: [
          name: "GridUniforms",
          binding: 0,
          fields: [
            line_color: :vec4,
            background: :vec4,
            spacing: :vec2,
            thickness: :f32
          ]
        ]
      ],
      samplers: [],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  @impl true
  def init(_ctx, opts) do
    with {:ok, program} <- Shader.load() do
      {:ok,
       %__MODULE__{
         program: program,
         geometry: Geometry.fullscreen_quad(),
         spacing: fetch_spacing!(opts),
         thickness: Keyword.get(opts, :thickness, 1.0) * 1.0,
         line_color: Keyword.get(opts, :line_color, {0.3, 0.3, 0.35, 1.0}),
         background: Keyword.get(opts, :background, {0.08, 0.08, 0.1, 1.0})
       }}
    end
  end

  @impl true
  def update(state, opts) do
    {:ok,
     %{
       state
       | spacing: if(Keyword.has_key?(opts, :spacing), do: fetch_spacing!(opts), else: state.spacing),
         thickness: Keyword.get(opts, :thickness, state.thickness) * 1.0,
         line_color: Keyword.get(opts, :line_color, state.line_color),
         background: Keyword.get(opts, :background, state.background)
     }}
  end

  @impl true
  def draw(state, _frame) do
    state.program
    |> Program.bind()
    |> Program.set_block(:per_frame, %{
      line_color: state.line_color,
      background: state.background,
      spacing: state.spacing,
      thickness: state.thickness
    })

    Geometry.draw(state.geometry)

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Geometry.delete(state.geometry)
    Program.delete(state.program)
    :ok
  end

  defp fetch_spacing!(opts) do
    case Keyword.get(opts, :spacing, {0.1, 0.1}) do
      {x, y} when is_number(x) and is_number(y) and x > 0 and y > 0 ->
        {x * 1.0, y * 1.0}

      other ->
        raise ArgumentError,
              ":spacing must be {x, y} of positive numbers, got #{inspect(other)}"
    end
  end
end
