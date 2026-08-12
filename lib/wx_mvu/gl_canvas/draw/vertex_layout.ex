defmodule WxMVU.GLCanvas.Draw.VertexLayout do
  @moduledoc """
  Vertex attribute layout: stride and offsets, computed rather than counted.

  A layout is declared as an ordered keyword list of `{name, {type, count}}`:

      [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]

  from which this module derives the attribute index, byte offset and stride.
  Both `WxMVU.GLCanvas.Draw.Program` (at compile time) and
  `WxMVU.GLCanvas.Draw.Geometry` (at run time) use it, so a program and the
  geometry it draws cannot disagree about the layout.

  Before this existed, every canvas hand-computed its own:

      GL.vertex_attrib_pointer(0, 2, :float, false, 16, 0)
      GL.vertex_attrib_pointer(1, 2, :float, false, 16, 8)

  The `16` and `8` there are a stride and an offset worked out by hand, and
  nothing checked them against the shader they fed.
  """

  @type scalar :: :f32 | :i32 | :u32 | :i16 | :u16 | :i8 | :u8

  @type declaration :: [{atom(), {scalar(), pos_integer()}}]

  @type attribute :: %{
          name: atom(),
          index: non_neg_integer(),
          count: pos_integer(),
          type: atom(),
          normalized: boolean(),
          offset: non_neg_integer()
        }

  @doc """
  Computes attributes and stride from a declaration.

  Attribute indices are assigned in declaration order, matching the
  `layout(location = N)` numbering rust-gpu assigns to entry point parameters.
  """
  @spec normalize(declaration()) :: {[attribute()], non_neg_integer()}
  def normalize(declaration) do
    {attributes, stride} =
      declaration
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {{name, {type, count}}, index}, offset ->
        attribute = %{
          name: name,
          index: index,
          count: count,
          type: gl_type(type),
          normalized: false,
          offset: offset
        }

        {attribute, offset + size(type) * count}
      end)

    names = Enum.map(attributes, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> {attributes, stride}
      dupes -> raise ArgumentError, "duplicate vertex attributes: #{inspect(Enum.uniq(dupes))}"
    end
  end

  @doc "Size of one component, in bytes."
  @spec size(scalar()) :: pos_integer()
  def size(t) when t in [:f32, :i32, :u32], do: 4
  def size(t) when t in [:i16, :u16], do: 2
  def size(t) when t in [:i8, :u8], do: 1

  def size(other) do
    raise ArgumentError, "unsupported vertex attribute type: #{inspect(other)}"
  end

  @doc "Maps a declaration type onto the atom `Renderer.GL` expects."
  @spec gl_type(scalar()) :: atom()
  def gl_type(:f32), do: :float
  def gl_type(:i32), do: :int
  def gl_type(:u32), do: :unsigned_int
  def gl_type(:i16), do: :short
  def gl_type(:u16), do: :unsigned_short
  def gl_type(:i8), do: :byte
  def gl_type(:u8), do: :unsigned_byte

  def gl_type(other) do
    raise ArgumentError, "unsupported vertex attribute type: #{inspect(other)}"
  end
end
