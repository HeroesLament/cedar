defmodule WxMVU.GLCanvas.Draw.Geometry do
  @moduledoc """
  A vertex array, its buffer, and the layout describing it, as one value.

  Replaces the VAO/VBO/`vertex_attrib_pointer` sequence every canvas
  hand-rolled, which was identical in each of them apart from the numbers.

      geometry =
        Geometry.new(
          vertices,
          layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}],
          mode: :triangle_strip
        )

      Geometry.draw(geometry)

  Stride and offsets come from `WxMVU.GLCanvas.Draw.VertexLayout`, the same
  module a `Program` uses for its declaration, so geometry and shader cannot
  disagree about the layout.

  All functions require a current GL context.
  """

  alias WxMVU.GLCanvas.Draw.VertexLayout
  alias WxMVU.Renderer.GL

  @type t :: %__MODULE__{
          vao: non_neg_integer(),
          vbo: non_neg_integer(),
          ebo: non_neg_integer() | nil,
          mode: atom(),
          vertex_count: non_neg_integer(),
          index_count: non_neg_integer() | nil,
          index_type: atom() | nil,
          stride: non_neg_integer(),
          attributes: [VertexLayout.attribute()]
        }

  defstruct [
    :vao,
    :vbo,
    :ebo,
    :mode,
    :vertex_count,
    :index_count,
    :index_type,
    :stride,
    :attributes
  ]

  @doc """
  Uploads vertex data and configures a vertex array for it.

  ## Options

    * `:layout` - required, a `VertexLayout` declaration
    * `:mode` - primitive type, default `:triangles`
    * `:usage` - `:static` (default), `:dynamic` or `:stream`
    * `:indices` - optional index binary, making this an indexed draw
    * `:index_type` - `:unsigned_int` (default), `:unsigned_short`, `:unsigned_byte`
  """
  @spec new(binary(), keyword()) :: t()
  def new(vertices, opts) when is_binary(vertices) do
    declaration = Keyword.fetch!(opts, :layout)
    mode = Keyword.get(opts, :mode, :triangles)
    usage = Keyword.get(opts, :usage, :static)
    indices = Keyword.get(opts, :indices)
    index_type = Keyword.get(opts, :index_type, :unsigned_int)

    {attributes, stride} = VertexLayout.normalize(declaration)

    if stride == 0 do
      raise ArgumentError, "vertex layout is empty"
    end

    if rem(byte_size(vertices), stride) != 0 do
      raise ArgumentError,
            "vertex data is #{byte_size(vertices)} bytes, which is not a multiple " <>
              "of the #{stride}-byte stride implied by the layout"
    end

    vao = GL.create_vertex_array()
    vbo = GL.create_buffer()

    GL.bind_vertex_array(vao)
    GL.bind_buffer(:array, vbo)
    GL.buffer_data(:array, vertices, usage)

    Enum.each(attributes, fn attribute ->
      GL.vertex_attrib_pointer(
        attribute.index,
        attribute.count,
        attribute.type,
        attribute.normalized,
        stride,
        attribute.offset
      )

      GL.enable_vertex_attrib_array(attribute.index)
    end)

    {ebo, index_count} = maybe_indices(indices, index_type, usage)

    # Unbind so a later stray bind_buffer cannot corrupt this VAO's state.
    GL.bind_vertex_array(0)

    %__MODULE__{
      vao: vao,
      vbo: vbo,
      ebo: ebo,
      mode: mode,
      vertex_count: div(byte_size(vertices), stride),
      index_count: index_count,
      index_type: index_type,
      stride: stride,
      attributes: attributes
    }
  end

  defp maybe_indices(nil, _type, _usage), do: {nil, nil}

  defp maybe_indices(indices, type, usage) do
    ebo = GL.create_buffer()
    GL.bind_buffer(:element, ebo)
    GL.buffer_data(:element, indices, usage)
    {ebo, div(byte_size(indices), index_size(type))}
  end

  defp index_size(:unsigned_int), do: 4
  defp index_size(:unsigned_short), do: 2
  defp index_size(:unsigned_byte), do: 1

  @doc """
  A unit quad covering clip space, with texture coordinates.

  Layout is `[a_position: {:f32, 2}, a_texcoord: {:f32, 2}]` as a triangle
  strip. This is what every fullscreen-fragment visual draws, and it was
  reimplemented identically in every canvas that had one.
  """
  @spec fullscreen_quad() :: t()
  def fullscreen_quad do
    vertices =
      for {x, y, s, t} <- [
            {-1.0, -1.0, 0.0, 0.0},
            {1.0, -1.0, 1.0, 0.0},
            {-1.0, 1.0, 0.0, 1.0},
            {1.0, 1.0, 1.0, 1.0}
          ],
          into: <<>> do
        <<x::float-32-native, y::float-32-native, s::float-32-native, t::float-32-native>>
      end

    new(vertices,
      layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}],
      mode: :triangle_strip
    )
  end

  @doc "Replaces the vertex data. The new data must match the existing layout."
  @spec update(t(), binary()) :: t()
  def update(%__MODULE__{} = geometry, vertices) when is_binary(vertices) do
    if rem(byte_size(vertices), geometry.stride) != 0 do
      raise ArgumentError,
            "vertex data is #{byte_size(vertices)} bytes, not a multiple of the " <>
              "#{geometry.stride}-byte stride"
    end

    GL.bind_buffer(:array, geometry.vbo)
    GL.buffer_data(:array, vertices, :dynamic)

    %{geometry | vertex_count: div(byte_size(vertices), geometry.stride)}
  end

  @doc "Binds and draws. Uses `draw_elements` when the geometry has indices."
  @spec draw(t()) :: t()
  def draw(%__MODULE__{} = geometry) do
    GL.bind_vertex_array(geometry.vao)

    if geometry.ebo do
      GL.draw_elements(geometry.mode, geometry.index_count, geometry.index_type, 0)
    else
      GL.draw_arrays(geometry.mode, 0, geometry.vertex_count)
    end

    geometry
  end

  @doc "Releases the vertex array and its buffers."
  @spec delete(t()) :: :ok
  def delete(%__MODULE__{} = geometry) do
    GL.delete_vertex_array(geometry.vao)
    GL.delete_buffer(geometry.vbo)
    if geometry.ebo, do: GL.delete_buffer(geometry.ebo)
    :ok
  end
end
