defmodule Cedar.Visual.Viewport do
  @moduledoc """
  A 3D scene: one camera, many posed objects.

      {:ensure_visual, :viewport, :viewport, :root,
        notify: self(),
        camera: model.camera,
        nodes: [
          %{id: :base,  mesh: base_mesh,  transform: Math.identity()},
          %{id: :link1, mesh: link_mesh,  transform: pose_of(frames, 1)},
          %{id: :link2, mesh: link_mesh,  transform: pose_of(frames, 2)}
        ]}

  ## Why this exists when `:mesh` already draws lit geometry

  `:mesh` owns a camera. That is right for one object on its own and wrong the
  moment there are several: a six-link arm as six `:mesh` layers means six
  copies of the same eye and target, six shader programs compiled for the same
  shader, and a camera change that has to be written six times and can be
  written inconsistently. A scene has one camera by definition.

  So a viewport compiles the program once, keeps one camera, and draws each
  node with its own model matrix. Posing an arm is then N uniform writes and no
  uploads at all — which is what makes it viable to drive from forward
  kinematics every frame.

  ## Nodes

  A node is a map:

      %{id: :link1, mesh: mesh, transform: mat4, color: {r, g, b, a}}

  `:id` is what geometry is cached against, and it is the whole performance
  story. Geometry is uploaded when a node first appears or when its `:mesh`
  actually changes; a node whose transform changed and whose mesh did not is
  never re-uploaded. Reusing an id for different geometry is therefore
  meaningful, and reusing one carelessly means an upload per frame.

  `:transform` places the node in the world. `:color` defaults to a light grey.
  Both are cheap to change.

  ## Declared or sent

  `:nodes` works as an option and as data, the same split every Cedar visual
  makes. Declare them when poses change at human speed or through the model,
  which is the normal case even for animation — a trajectory played back
  through `view/1` at 30 Hz is a handful of matrices per frame. Send them with
  `send_data/2` when poses arrive faster than the model should be churned, such
  as live joint feedback off a fieldbus at hundreds of hertz.

  ## What this is not

  Not a scene graph. Nodes are a flat list in world space, with no parents and
  no inherited transforms. For a robot that is not a limitation but a
  recognition: forward kinematics already walks the tree and hands back a world
  pose per link, so a second tree here would be a second place for the same
  answer to be computed differently. Hierarchy belongs to whatever owns the
  kinematics.
  """

  use Cedar.Visual

  alias Cedar.{Camera, Math}
  alias Cedar.Renderer.GL
  alias Cedar.Visual.Mesh

  defstruct [:program, :camera, :light_direction, :depth_test, nodes: [], cache: %{}]

  @default_color {0.78, 0.78, 0.80, 1.0}

  defmodule Shader do
    @moduledoc false

    # The same shader `:mesh` uses, unchanged. Its uniform block is already
    # per-draw rather than per-frame, which is exactly what drawing many
    # objects with one program needs.
    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/mesh"},
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
      state = %__MODULE__{
        program: program,
        camera: camera!(Keyword.get(opts, :camera, Camera.new())),
        light_direction: Math.normalize(Keyword.get(opts, :light_direction, {-0.4, 0.85, 0.5})),
        depth_test: Keyword.get(opts, :depth_test, true)
      }

      {:ok, sync(state, Keyword.get(opts, :nodes, []))}
    end
  end

  @impl true
  def update(state, opts) do
    state = %{
      state
      | camera: camera!(Keyword.get(opts, :camera, state.camera)),
        light_direction:
          case Keyword.fetch(opts, :light_direction) do
            {:ok, direction} -> Math.normalize(direction)
            :error -> state.light_direction
          end,
        depth_test: Keyword.get(opts, :depth_test, state.depth_test)
    }

    case Keyword.fetch(opts, :nodes) do
      {:ok, nodes} -> {:ok, sync(state, nodes)}
      :error -> {:ok, state}
    end
  end

  @impl true
  def handle_data(state, {:nodes, nodes}) when is_list(nodes) do
    {:ok, sync(state, nodes)}
  end

  def handle_data(state, {:camera, camera}) do
    {:ok, %{state | camera: camera!(camera)}}
  end

  def handle_data(state, :clear), do: {:ok, sync(state, [])}

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, frame) do
    if state.nodes != [] do
      {width, height} = frame.pixel_size
      aspect = max(width, 1) / max(height, 1)

      # Once per frame, not once per node. This is the entire reason the
      # camera lives here rather than on each object.
      view_projection = Camera.view_projection(state.camera, aspect)

      if state.depth_test, do: GL.enable(:depth_test), else: GL.disable(:depth_test)

      program = Program.bind(state.program)

      Enum.each(state.nodes, fn item ->
        case Map.fetch(state.cache, item.id) do
          {:ok, %{geometry: geometry}} ->
            Program.set_block(program, :per_frame, %{
              mvp: Math.multiply(view_projection, item.transform),
              normal_matrix: Math.normal_matrix(item.transform),
              light_direction: state.light_direction,
              base_color: item.color
            })

            Geometry.draw(geometry)

          :error ->
            :ok
        end
      end)
    end

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Enum.each(state.cache, fn {_id, %{geometry: geometry}} -> Geometry.delete(geometry) end)
    Program.delete(state.program)
    :ok
  end

  @doc """
  The nodes currently held, in draw order.

  For tests and for a caller that wants to know what the viewport thinks it is
  showing.
  """
  @spec nodes(%__MODULE__{}) :: [map()]
  def nodes(%__MODULE__{nodes: nodes}), do: nodes

  # ==========================================================================

  # Reconciles the declared node list against the cached geometry: uploads what
  # is new, replaces what changed, releases what is gone, and leaves alone the
  # overwhelmingly common case of a node whose pose moved and whose shape did
  # not.
  defp sync(state, nodes) do
    nodes = Enum.map(nodes, &normalize!/1)

    ids = MapSet.new(nodes, & &1.id)

    {kept, dropped} = Map.split_with(state.cache, fn {id, _} -> MapSet.member?(ids, id) end)
    Enum.each(dropped, fn {_id, %{geometry: geometry}} -> Geometry.delete(geometry) end)

    # `item` rather than `node`: `node` is Kernel.node/0, and `node.mesh` reads
    # as a call to it rather than a field access.
    cache =
      Enum.reduce(nodes, kept, fn item, acc ->
        case Map.fetch(acc, item.id) do
          {:ok, %{mesh: cached, geometry: geometry}} ->
            if cached == item.mesh do
              # Same shape, new pose — the overwhelmingly common case, and the
              # one that must not touch the GPU.
              Map.put(acc, item.id, %{mesh: cached, geometry: geometry})
            else
              {vertices, indices} = Mesh.build(item.mesh)

              Map.put(acc, item.id, %{
                mesh: item.mesh,
                geometry: Geometry.replace(geometry, vertices, indices)
              })
            end

          :error ->
            Map.put(acc, item.id, %{mesh: item.mesh, geometry: build(item.mesh)})
        end
      end)

    %{state | nodes: nodes, cache: cache}
  end

  defp build(mesh) do
    {vertices, indices} = Mesh.build(mesh)

    Geometry.new(vertices,
      layout: @layout,
      mode: :triangles,
      usage: :dynamic,
      indices: indices,
      index_type: :unsigned_int
    )
  end

  defp normalize!(%{id: id, mesh: mesh} = node) when is_map(mesh) do
    %{
      id: id,
      mesh: mesh,
      transform: Map.get(node, :transform) || Math.identity(),
      color: Map.get(node, :color) || @default_color
    }
  end

  defp normalize!(node) do
    raise ArgumentError,
          "a viewport node is %{id: id, mesh: mesh, transform: mat4, color: rgba}, " <>
            "got #{inspect(node)}"
  end

  defp camera!(%Camera{} = camera), do: camera
  defp camera!(opts) when is_list(opts), do: Camera.new(opts)

  defp camera!(other) do
    raise ArgumentError, ":camera must be a Cedar.Camera or a keyword list, got #{inspect(other)}"
  end
end
