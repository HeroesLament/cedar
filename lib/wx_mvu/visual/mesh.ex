defmodule WxMVU.Visual.Mesh do
  @moduledoc """
  Lit triangle geometry with a camera.

      {:ensure_visual, :arm, :mesh, :root,
        eye: {4.0, 3.0, 6.0},
        target: {0.0, 0.5, 0.0},
        base_color: {0.85, 0.55, 0.15, 1.0}}

      WxMVU.Visual.send_data(:arm, {:mesh, WxMVU.Visual.Mesh.box(1.0)})

  This is the one that makes a 3D viewport possible: robot links, imported
  tessellations, ground planes, anything with a surface. Shading is Lambert
  with an ambient floor — in a CAD viewport the job is reading *shape*, and a
  physically-plausible material model makes that harder, not easier.

  ## Options

    * `:model` — a `WxMVU.Math` 4x4 placing the mesh in the world, default
      identity
    * `:eye`, `:target`, `:up` — the camera, defaults `{3, 3, 3}`, the origin
      and `{0, 1, 0}`
    * `:fov` — vertical field of view in degrees, default `45.0`
    * `:near`, `:far` — clip planes, defaults `0.1` and `100.0`
    * `:base_color` — `{r, g, b, a}`, default a warm grey
    * `:light_direction` — direction *towards* the light in world space,
      normalized for you, default over the viewer's left shoulder
    * `:mesh` — geometry, as a declaration rather than as data

  A declared mesh is compared against the last one and only re-uploaded when
  it differs, because unlike a colour or a camera angle the geometry is the
  expensive thing here and `view/1` may well run every frame. Send it with
  `send_data/2` instead when it changes at frame rate — see
  `WxMVU.Visual.Line` for the same split argued at more length.
    * `:depth_test` — default `true`; turn it off for wireframe overlays

  Every one of these is a live uniform. Orbiting the camera writes 144 bytes;
  it does not touch the vertex buffer.

  ## Data

      {:mesh, mesh}   # replaces the geometry
      :clear          # draws nothing

  where `mesh` is a map:

      %{positions: [{x, y, z}, ...], indices: [{a, b, c}, ...]}
      %{positions: [...], normals: [...], indices: [...]}

  Normals are computed if you do not supply them — area-weighted across the
  faces meeting each vertex, which is the smooth-shading default. Supply them
  yourself for hard edges, or duplicate the vertices.

  The projection is rebuilt per frame from the framebuffer size, so a resized
  viewport keeps its aspect ratio without the application observing the resize.
  """

  use WxMVU.Visual

  alias WxMVU.Math
  alias WxMVU.Renderer.GL

  defstruct [
    :program,
    :geometry,
    :model,
    :eye,
    :target,
    :up,
    :fov,
    :near,
    :far,
    :base_color,
    :light_direction,
    :depth_test,
    :declared_mesh,
    index_count: 0
  ]

  defmodule Shader do
    @moduledoc false

    use WxMVU.GLCanvas.Draw.Program,
      source: {:priv, :wx_mvu, "shaders/mesh"},
      blocks: [
        per_frame: [
          name: "MeshUniforms",
          binding: 0,
          fields: [
            mvp: :mat4,
            normal_matrix: :mat3,
            light_direction: :vec3,
            base_color: :vec4
          ]
        ]
      ],
      samplers: [],
      vertex_layout: [a_position: {:f32, 3}, a_normal: {:f32, 3}]
  end

  @layout [a_position: {:f32, 3}, a_normal: {:f32, 3}]

  @impl true
  def init(_ctx, opts) do
    with {:ok, program} <- Shader.load() do
      mesh = Keyword.get(opts, :mesh)
      {vertices, indices} = build(mesh)

      geometry =
        Geometry.new(vertices,
          layout: @layout,
          mode: :triangles,
          usage: :dynamic,
          indices: indices,
          index_type: :unsigned_int
        )

      {:ok,
       %__MODULE__{
         program: program,
         geometry: geometry,
         model: Keyword.get(opts, :model, Math.identity()),
         eye: Keyword.get(opts, :eye, {3.0, 3.0, 3.0}),
         target: Keyword.get(opts, :target, {0.0, 0.0, 0.0}),
         up: Keyword.get(opts, :up, {0.0, 1.0, 0.0}),
         fov: Keyword.get(opts, :fov, 45.0) * 1.0,
         near: Keyword.get(opts, :near, 0.1) * 1.0,
         far: Keyword.get(opts, :far, 100.0) * 1.0,
         base_color: Keyword.get(opts, :base_color, {0.75, 0.75, 0.78, 1.0}),
         light_direction: Math.normalize(Keyword.get(opts, :light_direction, {-0.4, 0.8, 0.5})),
         depth_test: Keyword.get(opts, :depth_test, true),
         declared_mesh: mesh,
         index_count: div(byte_size(indices), 4)
       }}
    end
  end

  @impl true
  def update(state, opts) do
    state =
      case Keyword.fetch(opts, :mesh) do
        {:ok, mesh} when mesh != state.declared_mesh ->
          {vertices, indices} = build(mesh)

          %{
            state
            | geometry: Geometry.replace(state.geometry, vertices, indices),
              declared_mesh: mesh,
              index_count: div(byte_size(indices), 4)
          }

        _unchanged ->
          state
      end

    light =
      case Keyword.fetch(opts, :light_direction) do
        {:ok, direction} -> Math.normalize(direction)
        :error -> state.light_direction
      end

    {:ok,
     %{
       state
       | model: Keyword.get(opts, :model, state.model),
         eye: Keyword.get(opts, :eye, state.eye),
         target: Keyword.get(opts, :target, state.target),
         up: Keyword.get(opts, :up, state.up),
         fov: Keyword.get(opts, :fov, state.fov) * 1.0,
         near: Keyword.get(opts, :near, state.near) * 1.0,
         far: Keyword.get(opts, :far, state.far) * 1.0,
         base_color: Keyword.get(opts, :base_color, state.base_color),
         light_direction: light,
         depth_test: Keyword.get(opts, :depth_test, state.depth_test)
     }}
  end

  @impl true
  def handle_data(state, {:mesh, mesh}) do
    {vertices, indices} = build(mesh)

    geometry = Geometry.replace(state.geometry, vertices, indices)

    {:ok, %{state | geometry: geometry, index_count: div(byte_size(indices), 4)}}
  end

  def handle_data(state, :clear) do
    geometry = Geometry.replace(state.geometry, <<>>, <<>>)
    {:ok, %{state | geometry: geometry, index_count: 0}}
  end

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, frame) do
    if state.index_count > 0 do
      {width, height} = frame.pixel_size
      aspect = max(width, 1) / max(height, 1)

      view = Math.look_at(state.eye, state.target, state.up)
      projection = Math.perspective(state.fov, aspect, state.near, state.far)
      mvp = Math.multiply([projection, view, state.model])

      if state.depth_test, do: GL.enable(:depth_test), else: GL.disable(:depth_test)

      state.program
      |> Program.bind()
      |> Program.set_block(:per_frame, %{
        mvp: mvp,
        normal_matrix: Math.normal_matrix(state.model),
        light_direction: Tuple.to_list(state.light_direction),
        base_color: state.base_color
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
  # Geometry construction — pure, and tested without a GL context
  # ==========================================================================

  @doc """
  Turns a mesh map into the interleaved vertex binary and index binary the
  shader expects.

  Returns `{vertices, indices}`. `nil` and an empty mesh both yield two empty
  binaries rather than raising, because "no geometry yet" is the normal state
  of a visual between `init/2` and its first data.
  """
  @spec build(map() | nil) :: {binary(), binary()}
  def build(nil), do: {<<>>, <<>>}

  def build(%{positions: []}), do: {<<>>, <<>>}

  def build(%{positions: positions, indices: indices} = mesh) do
    count = Kernel.length(positions)

    # Before anything dereferences them. `smooth_normals/2` indexes the
    # position list directly, so an out-of-range index would otherwise surface
    # as `elem/2`'s "out of range" with no clue which triangle was at fault.
    flat_indices =
      indices
      |> Enum.flat_map(fn {a, b, c} -> [a, b, c] end)
      |> Enum.map(fn i ->
        if i < 0 or i >= count do
          raise ArgumentError, "index #{i} is out of range for #{count} vertices"
        end

        i
      end)

    normals =
      case Map.get(mesh, :normals) do
        nil ->
          smooth_normals(positions, indices)

        given when Kernel.length(given) == Kernel.length(positions) ->
          given

        given ->
          raise ArgumentError,
                "mesh has #{Kernel.length(positions)} positions but " <>
                  "#{Kernel.length(given)} normals"
      end

    vertices =
      positions
      |> Enum.zip(normals)
      |> Enum.map(fn {{px, py, pz}, {nx, ny, nz}} ->
        <<px * 1.0::float-32-native, py * 1.0::float-32-native, pz * 1.0::float-32-native,
          nx * 1.0::float-32-native, ny * 1.0::float-32-native, nz * 1.0::float-32-native>>
      end)
      |> IO.iodata_to_binary()

    index_binary =
      for i <- flat_indices, into: <<>>, do: <<i::unsigned-integer-32-native>>

    {vertices, index_binary}
  end

  def build(other) do
    raise ArgumentError,
          "a mesh is %{positions: [...], indices: [...]}, got #{inspect(other)}"
  end

  @doc """
  Area-weighted vertex normals.

  Each face contributes its cross product — whose magnitude is twice the face
  area — to all three of its vertices, and the sum is normalized at the end.
  Weighting by area rather than normalizing per face first is what stops a fan
  of slivers from outvoting the one large face a vertex actually belongs to.
  """
  @spec smooth_normals([Math.vec3()], [{integer(), integer(), integer()}]) :: [Math.vec3()]
  def smooth_normals(positions, indices) do
    vertices = List.to_tuple(positions)
    zero = {0.0, 0.0, 0.0}

    accumulated =
      Enum.reduce(indices, %{}, fn {a, b, c}, acc ->
        pa = elem(vertices, a)
        pb = elem(vertices, b)
        pc = elem(vertices, c)

        face = Math.cross(Math.sub(pb, pa), Math.sub(pc, pa))

        acc
        |> Map.update(a, face, &Math.add(&1, face))
        |> Map.update(b, face, &Math.add(&1, face))
        |> Map.update(c, face, &Math.add(&1, face))
      end)

    for i <- 0..(Kernel.length(positions) - 1) do
      Math.normalize(Map.get(accumulated, i, zero))
    end
  end

  @doc """
  An axis-aligned box centred on the origin.

  `size` is either a number for a cube or `{x, y, z}`. Faces do not share
  vertices, so the box has hard edges rather than the rounded look shared
  normals would give it.
  """
  @spec box(number() | Math.vec3()) :: map()
  def box(size \\ 1.0)
  def box(size) when is_number(size), do: box({size, size, size})

  def box({sx, sy, sz}) do
    hx = sx / 2.0
    hy = sy / 2.0
    hz = sz / 2.0

    faces = [
      # {normal, four corners counter-clockwise seen from outside}
      {{0.0, 0.0, 1.0}, [{-hx, -hy, hz}, {hx, -hy, hz}, {hx, hy, hz}, {-hx, hy, hz}]},
      {{0.0, 0.0, -1.0}, [{hx, -hy, -hz}, {-hx, -hy, -hz}, {-hx, hy, -hz}, {hx, hy, -hz}]},
      {{1.0, 0.0, 0.0}, [{hx, -hy, hz}, {hx, -hy, -hz}, {hx, hy, -hz}, {hx, hy, hz}]},
      {{-1.0, 0.0, 0.0}, [{-hx, -hy, -hz}, {-hx, -hy, hz}, {-hx, hy, hz}, {-hx, hy, -hz}]},
      {{0.0, 1.0, 0.0}, [{-hx, hy, hz}, {hx, hy, hz}, {hx, hy, -hz}, {-hx, hy, -hz}]},
      {{0.0, -1.0, 0.0}, [{-hx, -hy, -hz}, {hx, -hy, -hz}, {hx, -hy, hz}, {-hx, -hy, hz}]}
    ]

    {positions, normals} =
      faces
      |> Enum.flat_map(fn {normal, corners} -> Enum.map(corners, &{&1, normal}) end)
      |> Enum.unzip()

    indices =
      for face <- 0..5, triangle <- [{0, 1, 2}, {0, 2, 3}] do
        {a, b, c} = triangle
        {face * 4 + a, face * 4 + b, face * 4 + c}
      end

    %{positions: positions, normals: normals, indices: indices}
  end

  @doc """
  A flat rectangle in the XZ plane, facing up.

  `divisions` splits it into a grid, which matters as soon as there is
  per-vertex anything — a deformation, a heightmap, or just less obvious
  Gouraud banding.
  """
  @spec plane(number(), pos_integer()) :: map()
  def plane(size \\ 1.0, divisions \\ 1) when divisions >= 1 do
    half = size / 2.0
    step = size / divisions
    n = divisions + 1

    positions =
      for row <- 0..divisions, col <- 0..divisions do
        {-half + col * step, 0.0, -half + row * step}
      end

    normals = List.duplicate({0.0, 1.0, 0.0}, n * n)

    indices =
      for row <- 0..(divisions - 1), col <- 0..(divisions - 1), triangle <- [:a, :b] do
        tl = row * n + col
        tr = tl + 1
        bl = tl + n
        br = bl + 1

        case triangle do
          :a -> {tl, bl, br}
          :b -> {tl, br, tr}
        end
      end

    %{positions: positions, normals: normals, indices: indices}
  end
end
