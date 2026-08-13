defmodule Cedar.Visual.Image do
  @moduledoc """
  A 2D scalar field drawn through a colormap.

  One visual covering waterfalls, spectrograms, constellations, heatmaps and
  any other grid of numbers. The differences between those are parameters, not
  implementations:

      # a scrolling waterfall
      {:ensure_visual, :waterfall, :image, :root,
        grid: {512, 256}, domain: {-100.0, 0.0},
        colormap: :viridis, advance: :per_datum}

      # a static spectrogram over a fixed window
      {:ensure_visual, :spectrogram, :image, :root,
        grid: {512, 256}, domain: {-100.0, 0.0},
        colormap: :viridis, advance: :none}

      # an I/Q density plot
      {:ensure_visual, :constellation, :image, :root,
        grid: {128, 128}, domain: {0.0, 50.0},
        colormap: :plasma, advance: :none}

  ## Data

      Cedar.Visual.send_data(:waterfall, {:row, <<...>>})   # one row, advances
      Cedar.Visual.send_data(:constellation, {:grid, <<...>>})  # whole field
      Cedar.Visual.send_data(:waterfall, :clear)

  Rows are `:r32f` by default — one float per cell, native-endian.

  ## How the scroll works

  With `advance: :per_datum` the texture is a ring buffer. A new row overwrites
  the oldest and a `row_offset` uniform moves the seam, so nothing is ever
  copied: one row per datum reaches the GPU regardless of history depth. The
  scroll *rate* is therefore whatever rate data arrives at — the visual has no
  clock of its own.

  ## Options

    * `:grid` - `{width, height}`, required
    * `:domain` - `{min, max}` values mapped onto the colormap, required
    * `:colormap` - name or explicit stops, default `:viridis`
    * `:advance` - `:per_datum` (ring buffer) or `:none`, default `:none`
    * `:format` - texture format, default `:r32f`
    * `:fill` - initial value for every cell, default the domain minimum
    * `:filter` - `:linear` (default) or `:nearest`
    * `:data` - the whole field, as a declaration rather than as data

  `:filter` is `:linear` because a waterfall wants its history smoothed across
  the gaps between rows. Set it to `:nearest` when a cell is a *thing* rather
  than a sample of a continuum - a chessboard square, a tile map, a confusion
  matrix - where interpolating between neighbours invents a value that means
  nothing.

  `:data` is for a field that is a function of the model and changes at human
  speed: a board position, a small heatmap recomputed on a control change. It
  arrives through the differ, so it cannot race the visual into existence the
  way a `send_data/2` can. Sample data at frame rate still belongs in
  `{:row, ...}` or `{:grid, ...}`; see `Cedar.Visual.Line` for the same split
  argued at more length.
  """

  use Cedar.Visual

  defstruct [
    :program,
    :geometry,
    :data,
    :colormap_texture,
    :grid,
    :domain,
    :colormap,
    :advance,
    :format,
    :fill,
    current_row: 0
  ]

  defmodule Shader do
    @moduledoc false

    use Cedar.GLCanvas.Draw.Program,
      source: {:priv, :cedar, "shaders/image"},
      blocks: [
        per_frame: [
          name: "Uniforms",
          binding: 0,
          fields: [row_offset: :f32, domain_min: :f32, domain_max: :f32]
        ]
      ],
      samplers: [u_data: 0, u_colormap: 1],
      vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
  end

  @impl true
  def init(_ctx, opts) do
    {width, height} = grid = fetch_grid!(opts)
    {domain_min, _domain_max} = domain = fetch_domain!(opts)
    colormap = Keyword.get(opts, :colormap, :viridis)
    advance = fetch_advance!(opts)
    format = Keyword.get(opts, :format, :r32f)
    fill = Keyword.get(opts, :fill, domain_min)

    with {:ok, program} <- Shader.load() do
      data =
        Texture.new(width, height,
          format: format,
          filter: Keyword.get(opts, :filter, :linear),
          wrap_s: :clamp_to_edge,
          # Repeat on t, because the ring buffer's seam wraps.
          wrap_t: if(advance == :per_datum, do: :repeat, else: :clamp_to_edge)
        )

      Texture.fill(data, encode_fill(format, fill))

      if declared = Keyword.get(opts, :data) do
        upload_grid!(data, declared, grid, format)
      end

      {:ok,
       %__MODULE__{
         program: program,
         geometry: Geometry.fullscreen_quad(),
         data: data,
         colormap_texture: Colormap.texture(colormap),
         grid: grid,
         domain: domain,
         colormap: colormap,
         advance: advance,
         format: format,
         fill: fill
       }}
    end
  end

  @impl true
  def update(state, opts) do
    grid = Keyword.get(opts, :grid, state.grid)

    if grid != state.grid do
      # Reallocating the texture would drop the history it holds, and callers
      # expect a resize to be a fresh start rather than a smear.
      {:reinit, {:grid_changed, state.grid, grid}}
    else
      colormap = Keyword.get(opts, :colormap, state.colormap)

      colormap_texture =
        if colormap == state.colormap do
          state.colormap_texture
        else
          Texture.delete(state.colormap_texture)
          Colormap.texture(colormap)
        end

      # A declared field is re-uploaded whenever it is present, which for a
      # keyword list built fresh by view/1 means every update. That is 64
      # bytes for a chessboard and a few KB for a small heatmap - cheap enough
      # that comparing first would cost more than it saves.
      if declared = Keyword.get(opts, :data) do
        upload_grid!(state.data, declared, state.grid, state.format)
      end

      {:ok,
       %{
         state
         | domain: Keyword.get(opts, :domain, state.domain),
           colormap: colormap,
           colormap_texture: colormap_texture
       }}
    end
  end

  @impl true
  def handle_data(state, {:row, row}) when is_binary(row) do
    {width, height} = state.grid
    expected = width * state.data.bytes_per_pixel

    row = fit(row, expected, state)

    Texture.upload_row(state.data, state.current_row, row)

    next =
      case state.advance do
        :per_datum -> rem(state.current_row + 1, height)
        :none -> state.current_row
      end

    {:ok, %{state | current_row: next}}
  end

  def handle_data(state, {:grid, field}) when is_binary(field) do
    upload_grid!(state.data, field, state.grid, state.format)
    {:ok, state}
  end

  def handle_data(state, :clear) do
    Texture.fill(state.data, encode_fill(state.format, state.fill))
    {:ok, %{state | current_row: 0}}
  end

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, _frame) do
    {_width, height} = state.grid
    {domain_min, domain_max} = state.domain

    state.program
    |> Program.bind()
    |> Program.set_block(:per_frame, %{
      row_offset: state.current_row / height,
      domain_min: domain_min,
      domain_max: domain_max
    })

    Texture.bind(state.data, Program.texture_unit(state.program, :u_data))
    Texture.bind(state.colormap_texture, Program.texture_unit(state.program, :u_colormap))

    Geometry.draw(state.geometry)

    {:ok, state}
  end

  @impl true
  def destroy(state) do
    Geometry.delete(state.geometry)
    Texture.delete(state.data)
    Texture.delete(state.colormap_texture)
    Program.delete(state.program)
    :ok
  end

  # ==========================================================================

  # A short row is padded with the fill value and a long one truncated, rather
  # than raising. FFT sizes drift at the edges of a stream and dropping the
  # frame outright is worse than showing it slightly wrong.
  defp fit(row, expected, _state) when byte_size(row) == expected, do: row

  defp fit(row, expected, state) when byte_size(row) < expected do
    pixel = encode_fill(state.format, state.fill)
    missing = div(expected - byte_size(row), state.data.bytes_per_pixel)
    row <> :binary.copy(pixel, missing)
  end

  defp fit(row, expected, _state), do: binary_part(row, 0, expected)

  defp upload_grid!(texture, field, {width, height}, format) do
    expected = width * height * texture.bytes_per_pixel

    if byte_size(field) != expected do
      raise ArgumentError,
            "a #{width}x#{height} #{format} grid is #{expected} bytes, " <>
              "got #{byte_size(field)}"
    end

    Texture.upload(texture, field)
  end

  defp encode_fill(:r32f, value), do: <<value * 1.0::float-32-native>>
  defp encode_fill(:r8, value), do: <<trunc(value)::8>>
  defp encode_fill(:rgba8, {r, g, b, a}), do: <<r::8, g::8, b::8, a::8>>

  defp encode_fill(format, value) do
    raise ArgumentError, "cannot encode #{inspect(value)} as a #{inspect(format)} fill"
  end

  defp fetch_grid!(opts) do
    case Keyword.fetch(opts, :grid) do
      {:ok, {w, h}} when is_integer(w) and is_integer(h) and w > 0 and h > 0 ->
        {w, h}

      {:ok, other} ->
        raise ArgumentError,
              ":grid must be {width, height} of positive integers, got #{inspect(other)}"

      :error ->
        raise ArgumentError, ":image requires a :grid, e.g. grid: {512, 256}"
    end
  end

  defp fetch_domain!(opts) do
    case Keyword.fetch(opts, :domain) do
      {:ok, {min, max}} when is_number(min) and is_number(max) ->
        {min * 1.0, max * 1.0}

      {:ok, other} ->
        raise ArgumentError, ":domain must be {min, max}, got #{inspect(other)}"

      :error ->
        raise ArgumentError, ":image requires a :domain, e.g. domain: {-100.0, 0.0}"
    end
  end

  defp fetch_advance!(opts) do
    case Keyword.get(opts, :advance, :none) do
      advance when advance in [:none, :per_datum] ->
        advance

      other ->
        raise ArgumentError,
              ":advance must be :none or :per_datum, got #{inspect(other)}"
    end
  end
end
