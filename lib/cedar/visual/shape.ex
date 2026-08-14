defmodule Cedar.Visual.Shape do
  @moduledoc """
  Analytic 2D primitives — rectangles, rounded rectangles, circles, ellipses,
  sectors and arcs — filled, stroked, and painted with solid colour or a
  gradient.

      {:ensure_visual, :panel, :shape, :root,
        shape: :rounded_rect,
        rect: {40, 40, 240, 120},
        radius: 8,
        fill: {0.16, 0.17, 0.20, 1.0},
        stroke: {1.0, {0.32, 0.34, 0.40, 1.0}}}

  This is the primitive set a GUI is actually made of. Buttons, panels, cards,
  inputs, focus rings, selection highlights, scrollbar thumbs, badges, progress
  arcs — all of them are one of these six shapes with a fill and maybe a
  stroke.

  ## Why a formula rather than a mesh

  The usual approach tessellates: flatten each corner arc into segments, fan
  the interior into triangles, rebuild the buffer whenever the size or radius
  changes, and pick a segment count that looks smooth zoomed in without being
  wasteful zoomed out. Stroking then wants a second, different mesh with its
  own joins and caps.

  Evaluating a signed distance function per fragment avoids all of it. The
  shape is exact at any size, antialiasing falls out of the distance for free,
  and the stroke is the same distance with one subtraction — so a fill and its
  outline can never disagree about where the edge is. Animating a corner radius
  changes a uniform rather than rebuilding geometry.

  ## Coordinates

  Everything is in logical pixels with the origin at the top left, the same
  space `:text` uses, because that is what a layout produces. Antialiasing is
  corrected to physical pixels internally, which is what stops edges going soft
  on a Retina display.

  ## Options

    * `:shape` — `:rect`, `:rounded_rect`, `:circle`, `:ellipse`, `:sector` or
      `:arc`. Default `:rect`.
    * `:rect` — `{x, y, width, height}` in logical pixels. Required.
    * `:radius` — corner radius, a number or `{tl, tr, br, bl}` clockwise from
      the top left. Default `0`. Ignored except for boxes.
    * `:fill` — `{r, g, b, a}`, a gradient (below), or `:none`. Default opaque
      white.
    * `:stroke` — `{width, {r, g, b, a}}` or `:none`. Default `:none`.
    * `:angles` — `{start, finish}` in radians for `:sector` and `:arc`,
      measured clockwise from the positive X axis. Default a full turn.
    * `:thickness` — band thickness for `:arc`, in logical pixels. Default `4`.
    * `:inset` — grows the shape by this many pixels; negative shrinks it.
      Default `0`.

  ## Gradients

      fill: {:linear, {x0, y0}, {x1, y1}, start_color, end_color}
      fill: {:radial, {cx, cy}, radius, inner_color, outer_color}

  Gradient coordinates are in the same space as `:rect`, so they can be written
  in terms of the shape's own box rather than in some private local frame.

  ## Circles and ellipses

  `:circle` is not a separate code path. A square whose corner radius is half
  its side *is* a circle — exactly, not approximately — so `:circle` sets the
  radius for you and takes the rounded-box path. An `:ellipse` genuinely does
  need its own distance function and gets one.

  ## Sectors and arcs

  A `:sector` is a filled pie slice from the centre. An `:arc` is a band of a
  ring, `:thickness` wide, sitting inside the box. Both are defined opening
  along +Y and rotated into place by the host, and every angle is converted to
  a sine and cosine before it reaches the GPU — so the shader contains no
  trigonometry and never depends on `atan2`, whose precision and branch cut
  vary across drivers.

  ## One shape per visual

  Deliberately, for now. It matches how Scenic models a graph node and keeps
  the uniform block readable. Batching many shapes into one draw call is an
  optimisation to make when a real UI has enough of them to justify it, and it
  does not change this interface.
  """

  use Cedar.Visual

  alias Cedar.Renderer.GL

  defstruct [
    :program,
    :geometry,
    :kind,
    :shape,
    :rect,
    :radii,
    :fill,
    :fill1,
    :gradient,
    :gradient_kind,
    :stroke_color,
    :stroke_width,
    :wedge,
    :arc,
    :inset
  ]

  defmodule Shader do
    @moduledoc false

    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/shape"},
      blocks: [
        per_frame: [
          name: "ShapeUniforms",
          binding: 0,
          fields: [
            fill_color: :vec4,
            fill_color1: :vec4,
            stroke_color: :vec4,
            radii: :vec4,
            rect: :vec4,
            gradient: :vec4,
            wedge: :vec4,
            viewport: :vec2,
            arc: :vec2,
            stroke_width: :f32,
            shape: :f32,
            gradient_kind: :f32,
            inset: :f32,
            pixel_scale: :f32
          ]
        ]
      ],
      samplers: [],
      vertex_layout: [a_corner: {:f32, 2}]
  end

  @layout [a_corner: {:f32, 2}]

  # A unit quad as two triangles. The vertex shader expands it to the shape's
  # box plus a margin, so this never changes and is shared by every shape.
  @unit_quad [
    {0.0, 0.0},
    {1.0, 0.0},
    {0.0, 1.0},
    {0.0, 1.0},
    {1.0, 0.0},
    {1.0, 1.0}
  ]

  @shapes %{rect: 0.0, rounded_rect: 0.0, circle: 0.0, ellipse: 1.0, sector: 2.0, arc: 3.0}

  @impl true
  def init(_ctx, opts) do
    with {:ok, program} <- Shader.load() do
      {:ok, apply_opts(%__MODULE__{program: program, geometry: unit_quad()}, opts, :init)}
    end
  end

  @impl true
  def update(state, opts), do: {:ok, apply_opts(state, opts, :update)}

  @impl true
  def draw(state, frame) do
    {width, height} = frame.logical_size

    GL.enable(:blend)
    GL.blend_func(:alpha)

    state.program
    |> Program.bind()
    |> Program.set_block(:per_frame, %{
      fill_color: state.fill,
      fill_color1: state.fill1,
      stroke_color: state.stroke_color,
      radii: state.radii,
      rect: state.rect,
      gradient: state.gradient,
      wedge: state.wedge,
      viewport: {width * 1.0, height * 1.0},
      arc: state.arc,
      stroke_width: state.stroke_width,
      shape: state.shape,
      gradient_kind: state.gradient_kind,
      inset: state.inset,
      pixel_scale: (frame.dpi_scale || 1.0) * 1.0
    })

    Geometry.draw(state.geometry)

    # Restored rather than left on, so the next visual on this canvas gets the
    # state it expects.
    GL.disable(:blend)

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Geometry.delete(state.geometry)
    Program.delete(state.program)
    :ok
  end

  # ==========================================================================

  defp unit_quad do
    vertices =
      for {x, y} <- @unit_quad, into: <<>> do
        <<x::float-32-native, y::float-32-native>>
      end

    Geometry.new(vertices, layout: @layout, mode: :triangles, usage: :static)
  end

  # `phase` distinguishes a first build, where every option needs a default,
  # from an update, where an absent option means "leave it alone". Without the
  # distinction a colour change would silently reset the geometry.
  defp apply_opts(state, opts, phase) do
    kind = get(opts, :shape, phase, state.kind, :rect)
    rect = get(opts, :rect, phase, state.rect, nil) |> normalize_rect!()

    radius = get(opts, :radius, phase, nil, 0)
    radii = resolve_radii(kind, rect, radius, state, opts, phase)

    {fill, fill1, gradient, gradient_kind} =
      case get(opts, :fill, phase, :keep, {1.0, 1.0, 1.0, 1.0}) do
        :keep -> {state.fill, state.fill1, state.gradient, state.gradient_kind}
        paint -> resolve_paint!(paint, rect)
      end

    {stroke_width, stroke_color} =
      case get(opts, :stroke, phase, :keep, :none) do
        :keep -> {state.stroke_width, state.stroke_color}
        stroke -> resolve_stroke!(stroke)
      end

    angles = get(opts, :angles, phase, nil, {0.0, 2 * :math.pi()})
    thickness = get(opts, :thickness, phase, nil, 4.0)

    %{
      state
      | kind: kind,
        shape: Map.fetch!(@shapes, kind),
        rect: rect,
        radii: radii,
        fill: fill,
        fill1: fill1,
        gradient: gradient,
        gradient_kind: gradient_kind,
        stroke_width: stroke_width * 1.0,
        stroke_color: stroke_color,
        wedge: wedge(angles),
        arc: arc_band(rect, thickness),
        inset: get(opts, :inset, phase, state.inset, 0) * 1.0
    }
  end

  # On init, an absent option falls back to `default`. On update it falls back
  # to `current`, which is the existing state.
  defp get(opts, key, :init, _current, default), do: Keyword.get(opts, key, default)
  defp get(opts, key, :update, current, _default), do: Keyword.get(opts, key, current)

  defp normalize_rect!({x, y, w, h})
       when is_number(x) and is_number(y) and is_number(w) and is_number(h) do
    {x * 1.0, y * 1.0, max(w * 1.0, 0.0), max(h * 1.0, 0.0)}
  end

  defp normalize_rect!(nil) do
    raise ArgumentError, ":rect is required, as {x, y, width, height} in logical pixels"
  end

  defp normalize_rect!(other) do
    raise ArgumentError, ":rect must be {x, y, width, height}, got #{inspect(other)}"
  end

  # A circle is a square with a half-side radius, so it needs no shape of its
  # own — but the radius has to come from somewhere, and it is the shorter
  # half-side rather than whatever the caller passed.
  defp resolve_radii(:circle, {_x, _y, w, h}, _radius, _state, _opts, _phase) do
    r = min(w, h) / 2.0
    {r, r, r, r}
  end

  defp resolve_radii(:rect, _rect, _radius, _state, _opts, _phase), do: {0.0, 0.0, 0.0, 0.0}

  defp resolve_radii(_kind, _rect, radius, state, opts, phase) do
    cond do
      Keyword.has_key?(opts, :radius) -> expand_radius!(radius)
      phase == :update and state.radii != nil -> state.radii
      true -> expand_radius!(radius || 0)
    end
  end

  defp expand_radius!(r) when is_number(r), do: {r * 1.0, r * 1.0, r * 1.0, r * 1.0}

  defp expand_radius!({tl, tr, br, bl})
       when is_number(tl) and is_number(tr) and is_number(br) and is_number(bl) do
    {tl * 1.0, tr * 1.0, br * 1.0, bl * 1.0}
  end

  defp expand_radius!(other) do
    raise ArgumentError,
          ":radius must be a number or {top_left, top_right, bottom_right, bottom_left}, " <>
            "got #{inspect(other)}"
  end

  # Gradient endpoints are given in the caller's coordinates and stored in the
  # shape's local frame, so the shader needs no extra translation and a moving
  # shape carries its gradient with it.
  defp resolve_paint!(:none, _rect), do: {{0.0, 0.0, 0.0, 0.0}, {0.0, 0.0, 0.0, 0.0}, zero4(), 0.0}

  defp resolve_paint!({:linear, {x0, y0}, {x1, y1}, c0, c1}, rect) do
    {cx, cy} = centre(rect)
    {colour!(c0), colour!(c1), {x0 - cx, y0 - cy, x1 - cx, y1 - cy}, 1.0}
  end

  defp resolve_paint!({:radial, {cx0, cy0}, radius, c0, c1}, rect) do
    {cx, cy} = centre(rect)
    {colour!(c0), colour!(c1), {cx0 - cx, cy0 - cy, radius * 1.0, 0.0}, 2.0}
  end

  defp resolve_paint!({_r, _g, _b, _a} = solid, _rect) do
    c = colour!(solid)
    {c, c, zero4(), 0.0}
  end

  defp resolve_paint!(other, _rect) do
    raise ArgumentError,
          ":fill must be {r, g, b, a}, :none, or a gradient tuple, got #{inspect(other)}"
  end

  defp resolve_stroke!(:none), do: {0.0, {0.0, 0.0, 0.0, 0.0}}

  defp resolve_stroke!({width, colour}) when is_number(width) do
    {max(width * 1.0, 0.0), colour!(colour)}
  end

  defp resolve_stroke!(other) do
    raise ArgumentError, ":stroke must be {width, {r, g, b, a}} or :none, got #{inspect(other)}"
  end

  defp colour!({r, g, b, a}) when is_number(r) and is_number(g) and is_number(b) and is_number(a) do
    {r * 1.0, g * 1.0, b * 1.0, a * 1.0}
  end

  defp colour!(other) do
    raise ArgumentError, "expected a colour as {r, g, b, a}, got #{inspect(other)}"
  end

  defp centre({x, y, w, h}), do: {x + w / 2.0, y + h / 2.0}

  defp zero4, do: {0.0, 0.0, 0.0, 0.0}

  @doc """
  Packs an angular span into the shader's wedge parameters.

  Returns `{cos_rotation, sin_rotation, sin_half_aperture, cos_half_aperture}`.

  The shader's sector and arc both open along +Y, so an arbitrary span becomes
  a rotation plus a half aperture. Rotating the mid-angle `m` onto +Y takes
  `pi/2 - m`, whose cosine and sine are `sin m` and `cos m` — which is why the
  first two components look transposed.

  Public because getting an angular convention wrong is invisible until
  something renders mirrored, and that is worth a test rather than an
  inspection.
  """
  @spec wedge({number(), number()}) :: {float(), float(), float(), float()}
  def wedge({start, finish}) when is_number(start) and is_number(finish) do
    mid = (start + finish) / 2.0

    # Clamped to a half turn: beyond that the wedge is the whole disc, and a
    # larger half-aperture would wrap around and start cutting it away again.
    half = min(abs(finish - start) / 2.0, :math.pi())

    {:math.sin(mid), :math.cos(mid), :math.sin(half), :math.cos(half)}
  end

  def wedge(other) do
    raise ArgumentError, ":angles must be {start, finish} in radians, got #{inspect(other)}"
  end

  # The band sits inside the box: the outer edge is the box's inscribed circle
  # and the thickness grows inwards, so an arc never draws outside its rect.
  defp arc_band({_x, _y, w, h}, thickness) do
    outer = min(w, h) / 2.0
    half = min(max(thickness * 1.0, 0.0), outer * 2.0) / 2.0

    {max(outer - half, 0.0), half}
  end
end
