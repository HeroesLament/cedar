defmodule WxMVU.GLCanvas.Draw.Program do
  @moduledoc """
  Declarative shader programs for GL canvases.

  A program module declares its shader source, its uniform blocks, its sampler
  units and its vertex layout once. Everything else - std140 offsets, the
  packing function, the vertex stride, the uniform block plumbing - is derived.

  ## Why blocks rather than loose uniforms

  GLSL 410 has no `layout(binding = N)` for uniform blocks; that qualifier is
  GL 4.2. So the block/binding association is made at runtime by `load/1`.
  Uniform blocks (rather than individual `glUniform*` calls) are also what
  SPIR-V produces, so a canvas written against this API does not change shape
  when its GLSL starts being generated rather than hand-written.

  ## Declaring

      defmodule MyCanvas.Shader do
        use WxMVU.GLCanvas.Draw.Program,
          source: {:inline, vert: @vertex_shader, frag: @fragment_shader},
          blocks: [
            per_frame: [
              name: "Uniforms",
              binding: 0,
              fields: [row_offset: :f32, db_min: :f32, db_max: :f32]
            ]
          ],
          samplers: [u_spectrogram: 0, u_colormap: 1],
          vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
      end

  `:source` may reference module attributes. `:blocks`, `:samplers` and
  `:vertex_layout` must be literals, because their layouts are computed at
  compile time.

  Field order within a block is significant and must match the GLSL
  declaration - see `WxMVU.GLCanvas.Draw.Std140`.

  ## Using

      # in init/2, with the context current
      {:ok, program} = MyCanvas.Shader.load()

      # in render/1
      program
      |> Program.bind()
      |> Program.set_block(:per_frame, %{row_offset: 0.5, db_min: -100.0, db_max: 0.0})

  ## Source location

  `:source` is either `{:inline, vert: ..., frag: ...}` or
  `{:priv, :my_app, "shaders/name"}`, the latter reading
  `priv/shaders/name.vert` and `priv/shaders/name.frag`. Moving from
  hand-written to generated GLSL is a change to this option and nothing else.
  """

  alias WxMVU.GLCanvas.Draw.Std140
  alias WxMVU.GLCanvas.Draw.VertexLayout
  alias WxMVU.Renderer.GL

  @type block_runtime :: %{
          name: String.t(),
          index: non_neg_integer(),
          binding: non_neg_integer(),
          ubo: non_neg_integer(),
          size: pos_integer(),
          layout: Std140.t()
        }

  @type t :: %__MODULE__{
          module: module(),
          id: non_neg_integer(),
          blocks: %{atom() => block_runtime()},
          samplers: %{atom() => %{location: integer(), unit: non_neg_integer()}},
          vertex_layout: [map()],
          stride: non_neg_integer()
        }

  defstruct [:module, :id, :blocks, :samplers, :vertex_layout, :stride]

  # ============================================================================
  # Macro
  # ============================================================================

  defmacro __using__(opts) do
    source = Keyword.fetch!(opts, :source)
    blocks = opts |> Keyword.get(:blocks, []) |> literal!(:blocks)
    samplers = opts |> Keyword.get(:samplers, []) |> literal!(:samplers)
    vertex_layout = opts |> Keyword.get(:vertex_layout, []) |> literal!(:vertex_layout)

    normalized_blocks = normalize_blocks(blocks)
    {attributes, stride} = VertexLayout.normalize(vertex_layout)

    layout_clauses =
      for block <- normalized_blocks do
        quote do
          def layout(unquote(block.key)), do: unquote(Macro.escape(block.layout))
        end
      end

    quote do
      alias WxMVU.GLCanvas.Draw.Program
      alias WxMVU.GLCanvas.Draw.Std140

      @doc "Shader source location, as declared."
      def source, do: unquote(source)

      @doc "Normalized uniform block declarations, in declaration order."
      def blocks, do: unquote(Macro.escape(normalized_blocks))

      @doc "Sampler uniform names mapped to texture units."
      def samplers, do: unquote(Macro.escape(samplers))

      @doc "Computed vertex attribute descriptors."
      def vertex_layout, do: unquote(Macro.escape(attributes))

      @doc "Computed vertex stride in bytes."
      def stride, do: unquote(stride)

      unquote(layout_clauses)

      def layout(key) do
        raise ArgumentError,
              "unknown uniform block #{inspect(key)} in #{inspect(__MODULE__)}; " <>
                "declared: #{inspect(Enum.map(blocks(), & &1.key))}"
      end

      @doc "std140 size of a block, in bytes."
      def block_size(key), do: layout(key).size

      @doc "Packs a full block into a binary matching its std140 layout."
      def pack(key, values), do: Std140.pack(layout(key), values)

      @doc "Compiles, links and validates the program. Requires a current context."
      def load, do: Program.load(__MODULE__)
    end
  end

  # ============================================================================
  # Compile-time normalization
  # ============================================================================

  defp literal!(ast, option) do
    if Macro.quoted_literal?(ast) do
      # Literal AST is its own value, but strip any remaining metadata.
      {value, _binding} = Code.eval_quoted(ast)
      value
    else
      raise ArgumentError,
            "#{inspect(option)} must be a literal so its layout can be computed " <>
              "at compile time, got: #{Macro.to_string(ast)}"
    end
  end

  defp normalize_blocks(blocks) do
    normalized =
      for {key, spec} <- blocks do
        %{
          key: key,
          name: fetch_block!(spec, :name, key),
          binding: fetch_block!(spec, :binding, key),
          fields: fetch_block!(spec, :fields, key),
          layout: Std140.layout(fetch_block!(spec, :fields, key))
        }
      end

    assert_unique!(Enum.map(normalized, & &1.key), "block names")
    assert_unique!(Enum.map(normalized, & &1.binding), "block bindings")

    normalized
  end

  defp fetch_block!(spec, option, key) do
    case Keyword.fetch(spec, option) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, "uniform block #{inspect(key)} is missing #{inspect(option)}"
    end
  end

  defp assert_unique!(values, what) do
    case values -- Enum.uniq(values) do
      [] -> :ok
      dupes -> raise ArgumentError, "duplicate #{what}: #{inspect(Enum.uniq(dupes))}"
    end
  end

  # ============================================================================
  # Loading
  # ============================================================================

  @doc """
  Compiles, links and validates a declared program.

  The GL context must be current. Returns `{:ok, program}` or
  `{:error, compile_or_link_log}`.

  Raises when the shader links but does not match its declaration - a missing
  block, a missing sampler, or a block whose driver-reported std140 size
  disagrees with the computed one. Those are programming errors, not runtime
  conditions, and failing loudly here is the entire point: the alternative is a
  black screen.
  """
  @spec load(module()) :: {:ok, t()} | {:error, String.t()}
  def load(module) do
    {vert, frag} = read_source(module.source())

    with {:ok, vs} <- GL.create_shader(:vertex, vert),
         {:ok, fs} <- compile_fragment(frag, vs),
         {:ok, id} <- link(vs, fs) do
      # Sampler units are program state, so the program must be current.
      GL.use_program(id)

      blocks = Map.new(module.blocks(), &setup_block(module, id, &1))
      samplers = Map.new(module.samplers(), &setup_sampler(id, &1))

      {:ok,
       %__MODULE__{
         module: module,
         id: id,
         blocks: blocks,
         samplers: samplers,
         vertex_layout: module.vertex_layout(),
         stride: module.stride()
       }}
    end
  end

  defp compile_fragment(frag, vs) do
    case GL.create_shader(:fragment, frag) do
      {:ok, fs} ->
        {:ok, fs}

      {:error, log} ->
        GL.delete_shader(vs)
        {:error, log}
    end
  end

  defp link(vs, fs) do
    result = GL.create_program(vs, fs)
    GL.delete_shader(vs)
    GL.delete_shader(fs)
    result
  end

  defp setup_block(module, id, %{key: key, name: name, binding: binding, layout: layout}) do
    index = GL.get_uniform_block_index!(id, name)
    driver_size = GL.get_active_uniform_block_data_size(id, index)

    if driver_size != layout.size do
      raise """
      uniform block #{inspect(name)} in #{inspect(module)} has a std140 size of \
      #{driver_size} bytes according to the driver, but #{layout.size} bytes were \
      computed from the declaration.

      Declared fields, with computed offsets:
      #{inspect(Std140.offsets(layout), pretty: true)}

      This means the field list does not match the GLSL block - usually a missing \
      field, an extra field, or the wrong order.
      """
    end

    GL.uniform_block_binding(id, index, binding)

    ubo = GL.create_buffer()
    GL.bind_buffer(:uniform, ubo)
    GL.buffer_data(:uniform, :binary.copy(<<0>>, layout.size), :dynamic)
    GL.bind_buffer_base(:uniform, binding, ubo)

    {key,
     %{name: name, index: index, binding: binding, ubo: ubo, size: layout.size, layout: layout}}
  end

  defp setup_sampler(id, {name, unit}) do
    location = GL.get_uniform_location!(id, Atom.to_string(name))
    GL.uniform_1i(location, unit)
    {name, %{location: location, unit: unit}}
  end

  defp read_source({:inline, opts}) do
    {Keyword.fetch!(opts, :vert), Keyword.fetch!(opts, :frag)}
  end

  defp read_source({:priv, app, base}) do
    dir =
      case :code.priv_dir(app) do
        {:error, :bad_name} ->
          raise ArgumentError, "no priv directory for application #{inspect(app)}"

        path ->
          List.to_string(path)
      end

    {read_shader!(dir, base, "vert"), read_shader!(dir, base, "frag")}
  end

  defp read_source(other) do
    raise ArgumentError,
          "invalid :source #{inspect(other)}; expected {:inline, vert:, frag:} " <>
            "or {:priv, app, base_path}"
  end

  defp read_shader!(dir, base, extension) do
    path = Path.join(dir, base <> "." <> extension)

    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read shader", path: path
    end
  end

  # ============================================================================
  # Runtime
  # ============================================================================

  @doc "Makes the program current and rebinds its uniform buffers."
  @spec bind(t()) :: t()
  def bind(%__MODULE__{} = program) do
    GL.use_program(program.id)

    Enum.each(program.blocks, fn {_key, block} ->
      GL.bind_buffer_base(:uniform, block.binding, block.ubo)
    end)

    program
  end

  @doc "Packs and uploads a whole uniform block."
  @spec set_block(t(), atom(), map()) :: t()
  def set_block(%__MODULE__{} = program, key, values) do
    block = fetch_runtime_block!(program, key)
    GL.bind_buffer(:uniform, block.ubo)
    GL.buffer_sub_data(:uniform, 0, program.module.pack(key, values))
    program
  end

  @doc """
  Uploads a single field of a uniform block.

  Cheaper than `set_block/3` when one value changes per frame and the rest are
  static.
  """
  @spec set_field(t(), atom(), atom(), term()) :: t()
  def set_field(%__MODULE__{} = program, key, field, value) do
    block = fetch_runtime_block!(program, key)
    {offset, data} = Std140.pack_field(block.layout, field, value)
    GL.bind_buffer(:uniform, block.ubo)
    GL.buffer_sub_data(:uniform, offset, data)
    program
  end

  @doc "Texture unit assigned to a declared sampler."
  @spec texture_unit(t(), atom()) :: non_neg_integer()
  def texture_unit(%__MODULE__{samplers: samplers}, name) do
    case Map.fetch(samplers, name) do
      {:ok, %{unit: unit}} ->
        unit

      :error ->
        raise ArgumentError,
              "unknown sampler #{inspect(name)}; declared: #{inspect(Map.keys(samplers))}"
    end
  end

  @doc """
  Issues `vertex_attrib_pointer`/`enable_vertex_attrib_array` for the declared
  layout. Call with the target VAO and vertex buffer bound.
  """
  @spec configure_vertex_attribs(t()) :: t()
  def configure_vertex_attribs(%__MODULE__{} = program) do
    Enum.each(program.vertex_layout, fn attribute ->
      GL.vertex_attrib_pointer(
        attribute.index,
        attribute.count,
        attribute.type,
        attribute.normalized,
        program.stride,
        attribute.offset
      )

      GL.enable_vertex_attrib_array(attribute.index)
    end)

    program
  end

  @doc "Deletes the program object and its uniform buffers."
  @spec delete(t()) :: :ok
  def delete(%__MODULE__{} = program) do
    Enum.each(program.blocks, fn {_key, block} -> GL.delete_buffer(block.ubo) end)
    GL.delete_program(program.id)
    :ok
  end

  defp fetch_runtime_block!(%__MODULE__{blocks: blocks}, key) do
    case Map.fetch(blocks, key) do
      {:ok, block} ->
        block

      :error ->
        raise ArgumentError,
              "unknown uniform block #{inspect(key)}; declared: #{inspect(Map.keys(blocks))}"
    end
  end
end
