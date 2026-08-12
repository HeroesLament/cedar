defmodule WxMVU.GLCanvas.Draw.Colormap do
  @moduledoc """
  Colour lookup tables, as data and as a 256x1 texture.

  A colormap maps a normalized value in `[0, 1]` onto a colour. Shaders sample
  it as a one-row texture, which is why the entries are generated here and
  uploaded rather than being computed per-fragment.

      Colormap.texture(:viridis)
      Colormap.texture([{0.0, {0, 0, 0}}, {1.0, {255, 255, 255}}])

  The named maps are the perceptually-uniform ones plus the conventional ones.
  `:viridis` is the sensible default for scientific data: it is monotonic in
  luminance, so it survives being printed in greyscale and does not invent
  features the data does not contain, which `:hot` and rainbow maps both do.

  `:turbo` is the exception worth knowing about. It is a rainbow, with all the
  usual objections, but it was designed to fix the worst of them and it earns
  its place on one specific job: a narrow bright feature over a wide dark
  floor, which is what an RF waterfall is. A thin carrier a few dB above the
  noise is legible in turbo and nearly invisible in viridis, because viridis
  spends its luminance range evenly and turbo spends it where the signal is.
  Reach for it when the question is "is there something there", not when it is
  "how much".
  """

  alias WxMVU.GLCanvas.Draw.Texture

  @entries 256

  @type stop :: {float(), {0..255, 0..255, 0..255}}
  @type name :: :viridis | :plasma | :inferno | :magma | :turbo | :hot | :grayscale
  @type spec :: name() | [stop()]

  @maps %{
    viridis: [
      {0.0, {68, 1, 84}},
      {0.25, {59, 82, 139}},
      {0.5, {33, 145, 140}},
      {0.75, {94, 201, 98}},
      {1.0, {253, 231, 37}}
    ],
    plasma: [
      {0.0, {13, 8, 135}},
      {0.25, {126, 3, 168}},
      {0.5, {204, 71, 120}},
      {0.75, {248, 149, 64}},
      {1.0, {240, 249, 33}}
    ],
    inferno: [
      {0.0, {0, 0, 4}},
      {0.25, {87, 16, 110}},
      {0.5, {188, 55, 84}},
      {0.75, {249, 142, 9}},
      {1.0, {252, 255, 164}}
    ],
    magma: [
      {0.0, {0, 0, 4}},
      {0.25, {81, 18, 124}},
      {0.5, {183, 55, 121}},
      {0.75, {252, 137, 97}},
      {1.0, {252, 253, 191}}
    ],
    turbo: [
      {0.0, {48, 18, 59}},
      {0.125, {70, 66, 161}},
      {0.25, {62, 122, 229}},
      {0.375, {31, 178, 219}},
      {0.5, {58, 222, 145}},
      {0.625, {150, 245, 76}},
      {0.75, {228, 216, 56}},
      {0.875, {248, 137, 39}},
      {1.0, {122, 4, 3}}
    ],
    hot: [
      {0.0, {0, 0, 0}},
      {0.33, {230, 0, 0}},
      {0.66, {255, 200, 0}},
      {1.0, {255, 255, 255}}
    ],
    grayscale: [
      {0.0, {0, 0, 0}},
      {1.0, {255, 255, 255}}
    ]
  }

  @doc "Names of the built-in colormaps."
  @spec names() :: [name()]
  def names, do: Map.keys(@maps) |> Enum.sort()

  @doc "Colour stops for a built-in colormap."
  @spec stops(name()) :: [stop()]
  def stops(name) when is_atom(name) do
    case Map.fetch(@maps, name) do
      {:ok, stops} ->
        stops

      :error ->
        raise ArgumentError,
              "unknown colormap #{inspect(name)}; known: #{inspect(names())}"
    end
  end

  @doc """
  Generates the lookup table as a 256-entry RGB8 binary.

  Pure, so the interpolation is testable without a GL context.
  """
  @spec data(spec()) :: binary()
  def data(name) when is_atom(name), do: name |> stops() |> data()

  def data(stops) when is_list(stops) do
    validate!(stops)

    for i <- 0..(@entries - 1), into: <<>> do
      {r, g, b} = sample(stops, i / (@entries - 1))
      <<r::8, g::8, b::8>>
    end
  end

  @doc """
  Uploads a colormap as a 256x1 RGB8 texture.

  One row rather than a true 1D texture, because `GL_TEXTURE_1D` is awkward in
  a core profile and buys nothing here. Shaders sample it at `y = 0.5`.
  """
  @spec texture(spec()) :: Texture.t()
  def texture(spec) do
    Texture.new(@entries, 1,
      format: :rgb8,
      data: data(spec),
      filter: :linear,
      wrap: :clamp_to_edge
    )
  end

  @doc "Colour at a position in `[0, 1]`, interpolated between stops."
  @spec sample([stop()], float()) :: {0..255, 0..255, 0..255}
  def sample(stops, t) do
    t = t |> max(0.0) |> min(1.0)

    case bracket(stops, t) do
      {:exact, colour} ->
        colour

      {:between, {t0, c0}, {t1, c1}} ->
        # t1 > t0 is guaranteed by validate!/1, so this cannot divide by zero.
        lerp(c0, c1, (t - t0) / (t1 - t0))
    end
  end

  # ==========================================================================

  # No separate single-stop clause: the `rest == []` branch below covers it.
  # An earlier version had `bracket([{_t, colour}], _t)`, where the two
  # underscored variables bind to the same value in Elixir - so it only matched
  # when the sample position happened to equal the stop position.
  defp bracket([{t0, c0} | rest], t) do
    case rest do
      [{t1, c1} | _] when t <= t1 ->
        if t <= t0, do: {:exact, c0}, else: {:between, {t0, c0}, {t1, c1}}

      [_ | _] ->
        bracket(rest, t)

      [] ->
        {:exact, c0}
    end
  end

  defp lerp({r0, g0, b0}, {r1, g1, b1}, ratio) do
    {
      round(r0 + (r1 - r0) * ratio),
      round(g0 + (g1 - g0) * ratio),
      round(b0 + (b1 - b0) * ratio)
    }
  end

  defp validate!(stops) do
    if length(stops) < 2 do
      raise ArgumentError, "a colormap needs at least two stops"
    end

    positions = Enum.map(stops, &elem(&1, 0))

    if positions != Enum.sort(positions) or length(Enum.uniq(positions)) != length(positions) do
      raise ArgumentError,
            "colormap stops must be strictly increasing, got #{inspect(positions)}"
    end

    :ok
  end
end
