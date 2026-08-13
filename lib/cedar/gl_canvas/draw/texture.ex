defmodule Cedar.GLCanvas.Draw.Texture do
  @moduledoc """
  A 2D texture and the format triple describing it, as one value.

  Replaces the `create_texture` / `bind` / `tex_image_2d` / four
  `tex_parameter` sequence every canvas hand-rolled, and removes the need for
  callers to know that an `:r32f` texture is uploaded as `:red` / `:float`
  while an `:rgba8` one is `:rgba` / `:unsigned_byte` — a pairing that is easy
  to get subtly wrong and produces a silently blank or garbled texture rather
  than an error.

      data = Texture.new(512, 256, format: :r32f, filter: :nearest, wrap_t: :repeat)
      Texture.upload_row(data, 12, row_binary)
      Texture.bind(data, 0)

  All functions require a current GL context.
  """

  alias Cedar.Renderer.GL

  @type format :: :r8 | :r32f | :rg32f | :rgb8 | :rgba8 | :rgba32f

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          format: format(),
          internal_format: atom(),
          pixel_format: atom(),
          pixel_type: atom(),
          bytes_per_pixel: pos_integer()
        }

  defstruct [
    :id,
    :width,
    :height,
    :format,
    :internal_format,
    :pixel_format,
    :pixel_type,
    :bytes_per_pixel
  ]

  # internal format, pixel format, pixel type, bytes per pixel
  @formats %{
    r8: {:r8, :red, :unsigned_byte, 1},
    r32f: {:r32f, :red, :float, 4},
    rg32f: {:rg, :rg, :float, 8},
    rgb8: {:rgb8, :rgb, :unsigned_byte, 3},
    rgba8: {:rgba8, :rgba, :unsigned_byte, 4},
    rgba32f: {:rgba32f, :rgba, :float, 16}
  }

  @doc """
  Allocates a texture, optionally uploading initial contents.

  ## Options

    * `:format` - one of `#{inspect(Map.keys(%{r8: 0, r32f: 0, rg32f: 0, rgb8: 0, rgba8: 0, rgba32f: 0}) |> Enum.sort())}`, default `:rgba8`
    * `:data` - initial contents; zero-filled when omitted
    * `:filter` - `:nearest` (default) or `:linear`, applied to both min and mag
    * `:wrap` - applied to both axes, default `:clamp_to_edge`
    * `:wrap_s`, `:wrap_t` - per-axis overrides

  `:nearest` is the default deliberately. Data textures — a spectrogram's
  magnitudes, a histogram's counts — are samples, not images, and interpolating
  between them invents values that were never measured.
  """
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []) when width > 0 and height > 0 do
    format = Keyword.get(opts, :format, :rgba8)
    filter = Keyword.get(opts, :filter, :nearest)
    wrap = Keyword.get(opts, :wrap, :clamp_to_edge)
    wrap_s = Keyword.get(opts, :wrap_s, wrap)
    wrap_t = Keyword.get(opts, :wrap_t, wrap)

    {internal, pixel_format, pixel_type, bytes} = fetch_format!(format)

    expected = width * height * bytes

    data =
      case Keyword.get(opts, :data) do
        nil ->
          :binary.copy(<<0>>, expected)

        given when byte_size(given) == expected ->
          given

        given ->
          raise ArgumentError,
                "#{width}x#{height} #{format} needs #{expected} bytes, got #{byte_size(given)}"
      end

    id = GL.create_texture()
    GL.bind_texture(:texture_2d, id)
    GL.tex_image_2d(width, height, internal, pixel_format, pixel_type, data)
    GL.tex_parameter(:min_filter, filter)
    GL.tex_parameter(:mag_filter, filter)
    GL.tex_parameter(:wrap_s, wrap_s)
    GL.tex_parameter(:wrap_t, wrap_t)

    %__MODULE__{
      id: id,
      width: width,
      height: height,
      format: format,
      internal_format: internal,
      pixel_format: pixel_format,
      pixel_type: pixel_type,
      bytes_per_pixel: bytes
    }
  end

  @doc "Replaces the whole texture."
  @spec upload(t(), binary()) :: t()
  def upload(%__MODULE__{} = texture, data) do
    upload_sub(texture, 0, 0, texture.width, texture.height, data)
  end

  @doc """
  Replaces a single row.

  The waterfall primitive: a ring-buffer texture takes one new row per datum
  and the shader offsets its sampling rather than the whole texture being
  rewritten.
  """
  @spec upload_row(t(), non_neg_integer(), binary()) :: t()
  def upload_row(%__MODULE__{} = texture, row, data) when row >= 0 do
    if row >= texture.height do
      raise ArgumentError, "row #{row} is outside a texture of height #{texture.height}"
    end

    upload_sub(texture, 0, row, texture.width, 1, data)
  end

  @doc "Replaces a rectangular region."
  @spec upload_sub(t(), non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer(), binary()) ::
          t()
  def upload_sub(%__MODULE__{} = texture, x, y, width, height, data) do
    expected = width * height * texture.bytes_per_pixel

    if byte_size(data) != expected do
      raise ArgumentError,
            "#{width}x#{height} of #{texture.format} needs #{expected} bytes, " <>
              "got #{byte_size(data)}"
    end

    if x + width > texture.width or y + height > texture.height do
      raise ArgumentError,
            "region #{width}x#{height} at (#{x}, #{y}) does not fit in a " <>
              "#{texture.width}x#{texture.height} texture"
    end

    GL.bind_texture(:texture_2d, texture.id)

    GL.tex_sub_image_2d(
      x,
      y,
      width,
      height,
      texture.pixel_format,
      texture.pixel_type,
      data
    )

    texture
  end

  @doc "Fills the texture with a repeated value, e.g. a spectrogram's floor."
  @spec fill(t(), binary()) :: t()
  def fill(%__MODULE__{} = texture, pixel) when is_binary(pixel) do
    if byte_size(pixel) != texture.bytes_per_pixel do
      raise ArgumentError,
            "a #{texture.format} pixel is #{texture.bytes_per_pixel} bytes, " <>
              "got #{byte_size(pixel)}"
    end

    upload(texture, :binary.copy(pixel, texture.width * texture.height))
  end

  @doc "Makes the texture active on a unit, for a sampler bound to that unit."
  @spec bind(t(), non_neg_integer()) :: t()
  def bind(%__MODULE__{} = texture, unit) do
    GL.active_texture(unit)
    GL.bind_texture(:texture_2d, texture.id)
    texture
  end

  @doc "Releases the texture."
  @spec delete(t()) :: :ok
  def delete(%__MODULE__{} = texture) do
    GL.delete_texture(texture.id)
    :ok
  end

  defp fetch_format!(format) do
    case Map.fetch(@formats, format) do
      {:ok, triple} ->
        triple

      :error ->
        raise ArgumentError,
              "unknown texture format #{inspect(format)}; " <>
                "known: #{inspect(Enum.sort(Map.keys(@formats)))}"
    end
  end
end
