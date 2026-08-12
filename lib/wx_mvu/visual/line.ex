defmodule WxMVU.Visual.Line do
  @moduledoc """
  A polyline with a width in pixels.

      {:ensure_visual, :trace, :line, :root,
        color: {0.2, 1.0, 0.4, 1.0},
        width: 2.0}

      WxMVU.Visual.send_data(:trace, {:points, [{-1.0, 0.0}, {0.0, 0.5}, {1.0, -0.3}]})

  Backs traces, scope sweeps, spectrum outlines, axis rules and anything else
  that is a run of connected points.

  ## Why this is geometry and not a line primitive

  `glLineWidth` above 1.0 is unreliable to unsupported in an OpenGL 4.1 core
  profile — it is one of the things Apple's frozen driver simply does not do.
  So every segment is expanded into a quad whose corners are offset along the
  segment's screen-space perpendicular, and the width stays constant in pixels
  regardless of zoom because the expansion happens after projection.

  ## Options

    * `:color` - `{r, g, b, a}` in `0.0..1.0`, default opaque white
    * `:width` - line width in pixels, default `1.0`
    * `:points` - initial points, otherwise sent as data

  ## Data

      {:points, [{x, y}, ...]}              # one polyline
      {:polylines, [[{x, y}, ...], ...]}    # several disjoint runs
      :clear                                 # draws nothing

  `:polylines` is not a convenience over calling `:points` repeatedly - it is
  the only way to draw disjoint runs at all, since each send replaces the
  whole buffer. Axis rules, tick marks and a dashed trace are all one draw
  call this way.

  Coordinates are in clip space for now: `-1.0..1.0` with the origin at centre.
  A transform stack belongs with the `Viewport` work, not here.
  """

  use WxMVU.Visual

  defstruct [:program, :geometry, :color, :width, point_count: 0]

  defmodule Shader do
    @moduledoc false

    use WxMVU.GLCanvas.Draw.Program,
      source: {:priv, :wx_mvu, "shaders/line"},
      blocks: [
        per_frame: [
          name: "LineUniforms",
          binding: 0,
          fields: [color: :vec4, viewport: :vec2, line_width: :f32]
        ]
      ],
      samplers: [],
      vertex_layout: [
        a_position: {:f32, 2},
        a_neighbor: {:f32, 2},
        a_side: {:f32, 1}
      ]
  end

  @layout [a_position: {:f32, 2}, a_neighbor: {:f32, 2}, a_side: {:f32, 1}]

  @impl true
  def init(_ctx, opts) do
    points = Keyword.get(opts, :points, [])

    with {:ok, program} <- Shader.load() do
      vertices = expand(points)

      {:ok,
       %__MODULE__{
         program: program,
         geometry: Geometry.new(vertices, layout: @layout, mode: :triangles, usage: :dynamic),
         color: Keyword.get(opts, :color, {1.0, 1.0, 1.0, 1.0}),
         width: Keyword.get(opts, :width, 1.0) * 1.0,
         point_count: length(points)
       }}
    end
  end

  @impl true
  def update(state, opts) do
    {:ok,
     %{
       state
       | color: Keyword.get(opts, :color, state.color),
         width: Keyword.get(opts, :width, state.width) * 1.0
     }}
  end

  @impl true
  def handle_data(state, {:points, points}) when is_list(points) do
    geometry = Geometry.update(state.geometry, expand(points))
    {:ok, %{state | geometry: geometry, point_count: length(points)}}
  end

  def handle_data(state, {:polylines, runs}) when is_list(runs) do
    vertices = runs |> Enum.map(&expand/1) |> IO.iodata_to_binary()

    # Every run of fewer than two points expands to nothing, so the count that
    # matters is how many vertices came out, not how many points went in.
    drawable = if vertices == <<>>, do: 0, else: 2

    {:ok, %{state | geometry: Geometry.update(state.geometry, vertices), point_count: drawable}}
  end

  def handle_data(state, :clear) do
    {:ok, %{state | geometry: Geometry.update(state.geometry, <<>>), point_count: 0}}
  end

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, frame) do
    if state.point_count >= 2 do
      {width, height} = frame.pixel_size

      state.program
      |> Program.bind()
      |> Program.set_block(:per_frame, %{
        color: state.color,
        viewport: {width * 1.0, height * 1.0},
        line_width: state.width
      })

      Geometry.draw(state.geometry)
    end

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Geometry.delete(state.geometry)
    Program.delete(state.program)
    :ok
  end

  # ==========================================================================

  @doc """
  Expands a polyline into triangle vertices for the line shader.

  Each segment becomes two triangles, six vertices, rather than a single strip
  across the whole line: a strip would need degenerate triangles at every joint
  and would make each segment's expansion depend on its neighbours' — a shared
  vertex cannot offset two ways at once.

  The shader derives its perpendicular from `a_neighbor - a_position`, so both
  ends of a segment must yield the *same* direction. The far end therefore
  carries a neighbour extrapolated along the segment rather than the near point,
  which would reverse the direction and turn the quad into a bowtie.

  Public so the expansion is testable without a GL context.
  """
  @spec expand([{number(), number()}]) :: binary()
  def expand(points) when length(points) < 2, do: <<>>

  def expand(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{x0, y0}, {x1, y1}] ->
      dx = x1 - x0
      dy = y1 - y0
      # Extrapolated so the far end sees the same direction as the near end.
      fx = x1 + dx
      fy = y1 + dy

      near_left = {x0, y0, x1, y1, 1.0}
      near_right = {x0, y0, x1, y1, -1.0}
      far_left = {x1, y1, fx, fy, 1.0}
      far_right = {x1, y1, fx, fy, -1.0}

      [near_left, near_right, far_left, far_left, near_right, far_right]
    end)
    |> Enum.map(fn {px, py, nx, ny, side} ->
      <<px * 1.0::float-32-native, py * 1.0::float-32-native, nx * 1.0::float-32-native,
        ny * 1.0::float-32-native, side::float-32-native>>
    end)
    |> IO.iodata_to_binary()
  end
end
