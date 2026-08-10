defmodule WxMVU.GLCanvas.Draw.Std140 do
  @moduledoc """
  std140 uniform block layout computation and packing.

  SPIR-V has no loose uniforms, so anything round-tripped through it comes back
  as a `layout(std140) uniform` block. This module implements the std140 rules
  so that block contents can be described once, in Elixir, and packed correctly
  without hand-counting byte offsets.

  ## Supported types

      :f32 :i32 :u32          scalars, 4 bytes
      :vec2 :vec3 :vec4       float vectors
      :mat3 :mat4             column-major matrices
      {:array, type, n}       fixed-length arrays

  ## The rules that actually bite

  Alignment is not the same as size:

  | Type        | Size | Alignment |
  |-------------|------|-----------|
  | scalar      | 4    | 4         |
  | `:vec2`     | 8    | 8         |
  | `:vec3`     | 12   | **16**    |
  | `:vec4`     | 16   | 16        |
  | `:mat3`     | 48   | 16        |
  | `:mat4`     | 64   | 16        |
  | array       | n x roundup(elem, 16) | 16 |

  * a `:vec3` occupies 12 bytes but the *next* field starts at the next
    multiple of 16
  * `:mat3` is 48 bytes, not 36 - each column is padded out to a `vec4`
  * every array element is padded to 16 bytes, so `{:array, :f32, 4}` is
    64 bytes, not 16
  * the block as a whole is rounded up to a multiple of 16

  ## Field order is significant

  Offsets are positional, so the field list must be in the same order as the
  GLSL declaration. This module deliberately does not reorder fields to save
  space - under the generated-shader pipeline that order comes from the Rust
  struct and must be preserved. `reorder_hint/1` reports when a reorder *would*
  save space, without doing it.

  ## Example

      iex> alias WxMVU.GLCanvas.Draw.Std140
      iex> layout = Std140.layout(max_value: :f32, color_low: :vec3, color_high: :vec3)
      iex> layout.size
      48
      iex> Std140.offsets(layout)[:color_high]
      32
  """

  defstruct entries: [], size: 0

  @type scalar :: :f32 | :i32 | :u32
  @type field_type ::
          scalar()
          | :vec2
          | :vec3
          | :vec4
          | :mat3
          | :mat4
          | {:array, field_type(), pos_integer()}

  @type entry :: %{
          name: atom(),
          type: field_type(),
          offset: non_neg_integer(),
          size: pos_integer()
        }

  @type t :: %__MODULE__{entries: [entry()], size: non_neg_integer()}

  @block_alignment 16

  # ============================================================================
  # Layout
  # ============================================================================

  @doc """
  Computes the std140 layout for an ordered list of `{name, type}` fields.

  Raises `ArgumentError` on an unknown type, a duplicate field name, or an
  empty field list.
  """
  @spec layout([{atom(), field_type()}]) :: t()
  def layout(fields) do
    fields = Enum.to_list(fields)

    if fields == [] do
      raise ArgumentError, "a uniform block must declare at least one field"
    end

    names = Enum.map(fields, &elem(&1, 0))

    case names -- Enum.uniq(names) do
      [] -> :ok
      dupes -> raise ArgumentError, "duplicate field names: #{inspect(Enum.uniq(dupes))}"
    end

    {entries, end_offset} =
      Enum.map_reduce(fields, 0, fn {name, type}, offset ->
        start = align_up(offset, alignment(type))
        entry = %{name: name, type: type, offset: start, size: size(type)}
        {entry, start + entry.size}
      end)

    %__MODULE__{entries: entries, size: align_up(end_offset, @block_alignment)}
  end

  @doc "Field name to byte offset, for tests and debugging."
  @spec offsets(t()) :: %{atom() => non_neg_integer()}
  def offsets(%__MODULE__{entries: entries}) do
    Map.new(entries, &{&1.name, &1.offset})
  end

  @doc """
  Returns `{:ok, saved_bytes}` when sorting fields by descending alignment
  would produce a smaller block, or `:none`.

  Advisory only - callers should surface this as a hint, never act on it.
  """
  @spec reorder_hint(t()) :: {:ok, pos_integer()} | :none
  def reorder_hint(%__MODULE__{entries: entries, size: size}) do
    best =
      entries
      |> Enum.map(&{&1.name, &1.type})
      |> Enum.sort_by(fn {_name, type} -> {-alignment(type), -size(type)} end)
      |> layout()

    if best.size < size, do: {:ok, size - best.size}, else: :none
  end

  # ============================================================================
  # Type metrics
  # ============================================================================

  @doc "Base alignment of a type, in bytes."
  @spec alignment(field_type()) :: pos_integer()
  def alignment(t) when t in [:f32, :i32, :u32], do: 4
  def alignment(:vec2), do: 8
  def alignment(:vec3), do: 16
  def alignment(:vec4), do: 16
  def alignment(:mat3), do: 16
  def alignment(:mat4), do: 16
  def alignment({:array, _type, _n}), do: 16
  def alignment(other), do: raise(ArgumentError, "unsupported std140 type: #{inspect(other)}")

  @doc """
  Size of a type in bytes, including any padding *interior* to the type.

  Does not include trailing padding needed to align whatever follows it - that
  is a property of the surrounding block, not of the type.
  """
  @spec size(field_type()) :: pos_integer()
  def size(t) when t in [:f32, :i32, :u32], do: 4
  def size(:vec2), do: 8
  def size(:vec3), do: 12
  def size(:vec4), do: 16
  # 3 columns, each a vec3 padded out to 16 bytes.
  def size(:mat3), do: 48
  # 4 columns of vec4, which need no padding.
  def size(:mat4), do: 64

  def size({:array, type, n}) when is_integer(n) and n > 0 do
    n * array_stride(type)
  end

  def size(other), do: raise(ArgumentError, "unsupported std140 type: #{inspect(other)}")

  @doc "Per-element stride of an array, i.e. element size rounded up to 16."
  @spec array_stride(field_type()) :: pos_integer()
  def array_stride(type), do: align_up(size(type), @block_alignment)

  # ============================================================================
  # Packing
  # ============================================================================

  @doc """
  Packs a map of field values into a binary matching the layout.

  Every field must be present; there is no implicit zero fill, because a
  silently zeroed uniform is the failure mode this module exists to prevent.
  Use `pack_field/3` with `buffer_sub_data` for partial updates.

  Values are `:f32` -> number, `:i32`/`:u32` -> integer, vectors -> tuple or
  list of the right arity, `:mat3` -> 9 floats column-major, `:mat4` -> 16
  floats column-major, arrays -> list of element values.
  """
  @spec pack(t(), map()) :: binary()
  def pack(%__MODULE__{entries: entries, size: size}, values) when is_map(values) do
    declared = MapSet.new(entries, & &1.name)
    given = MapSet.new(Map.keys(values))

    case MapSet.to_list(MapSet.difference(declared, given)) do
      [] -> :ok
      missing -> raise ArgumentError, "missing uniform fields: #{inspect(Enum.sort(missing))}"
    end

    case MapSet.to_list(MapSet.difference(given, declared)) do
      [] -> :ok
      extra -> raise ArgumentError, "unknown uniform fields: #{inspect(Enum.sort(extra))}"
    end

    {iodata, end_offset} =
      Enum.map_reduce(entries, 0, fn entry, offset ->
        gap = entry.offset - offset
        encoded = encode(entry.type, Map.fetch!(values, entry.name), entry.name)
        {[pad(gap), encoded], entry.offset + entry.size}
      end)

    IO.iodata_to_binary([iodata, pad(size - end_offset)])
  end

  @doc """
  Encodes a single field, returning `{offset, binary}` for use with
  `buffer_sub_data/3`.
  """
  @spec pack_field(t(), atom(), term()) :: {non_neg_integer(), binary()}
  def pack_field(%__MODULE__{entries: entries}, name, value) do
    case Enum.find(entries, &(&1.name == name)) do
      nil ->
        raise ArgumentError,
              "unknown uniform field #{inspect(name)}; " <>
                "declared: #{inspect(Enum.map(entries, & &1.name))}"

      entry ->
        {entry.offset, encode(entry.type, value, name)}
    end
  end

  # ============================================================================
  # Encoding
  # ============================================================================

  defp encode(:f32, v, name) when is_number(v), do: <<to_f32(v, name)::float-32-native>>
  defp encode(:i32, v, _name) when is_integer(v), do: <<v::signed-integer-32-native>>

  defp encode(:u32, v, _name) when is_integer(v) and v >= 0,
    do: <<v::unsigned-integer-32-native>>

  defp encode(:vec2, v, name), do: floats(v, 2, name)
  defp encode(:vec3, v, name), do: floats(v, 3, name)
  defp encode(:vec4, v, name), do: floats(v, 4, name)

  # Column-major, each vec3 column padded out to 16 bytes.
  defp encode(:mat3, v, name) do
    v
    |> to_list(name)
    |> assert_length(9, :mat3, name)
    |> Enum.chunk_every(3)
    |> Enum.map(&[floats(&1, 3, name), pad(4)])
    |> IO.iodata_to_binary()
  end

  defp encode(:mat4, v, name) do
    v |> to_list(name) |> assert_length(16, :mat4, name) |> floats(16, name)
  end

  defp encode({:array, type, n}, v, name) do
    stride = array_stride(type)

    v
    |> to_list(name)
    |> assert_length(n, {:array, type, n}, name)
    |> Enum.map(fn element ->
      encoded = encode(type, element, name)
      [encoded, pad(stride - byte_size(encoded))]
    end)
    |> IO.iodata_to_binary()
  end

  defp encode(type, v, name) do
    raise ArgumentError,
          "cannot encode #{inspect(v)} as #{inspect(type)} for field #{inspect(name)}"
  end

  defp floats(v, n, name) do
    v
    |> to_list(name)
    |> assert_length(n, {:floats, n}, name)
    |> Enum.map(&<<to_f32(&1, name)::float-32-native>>)
    |> IO.iodata_to_binary()
  end

  defp to_list(v, _name) when is_list(v), do: v
  defp to_list(v, _name) when is_tuple(v), do: Tuple.to_list(v)

  defp to_list(v, name) do
    raise ArgumentError,
          "field #{inspect(name)} expects a list or tuple, got #{inspect(v)}"
  end

  defp assert_length(list, n, type, name) do
    case length(list) do
      ^n ->
        list

      actual ->
        raise ArgumentError,
              "field #{inspect(name)} of type #{inspect(type)} expects #{n} " <>
                "components, got #{actual}"
    end
  end

  defp to_f32(v, _name) when is_number(v), do: v * 1.0

  defp to_f32(v, name) do
    raise ArgumentError, "field #{inspect(name)} expects a number, got #{inspect(v)}"
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp pad(0), do: <<>>
  defp pad(n) when n > 0, do: :binary.copy(<<0>>, n)

  @doc false
  def align_up(offset, alignment) do
    div(offset + alignment - 1, alignment) * alignment
  end
end
