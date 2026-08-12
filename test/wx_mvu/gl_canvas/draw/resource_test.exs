defmodule WxMVU.GLCanvas.Draw.VertexLayoutTest do
  use ExUnit.Case, async: true

  alias WxMVU.GLCanvas.Draw.VertexLayout

  doctest WxMVU.GLCanvas.Draw.VertexLayout

  describe "normalize/1" do
    test "computes the stride both existing canvases hand-wrote as 16" do
      {attributes, stride} =
        VertexLayout.normalize(a_position: {:f32, 2}, a_texcoord: {:f32, 2})

      assert stride == 16

      assert attributes == [
               %{
                 name: :a_position,
                 index: 0,
                 count: 2,
                 type: :float,
                 normalized: false,
                 offset: 0
               },
               %{
                 name: :a_texcoord,
                 index: 1,
                 count: 2,
                 type: :float,
                 normalized: false,
                 offset: 8
               }
             ]
    end

    test "assigns indices in declaration order" do
      {attributes, _stride} =
        VertexLayout.normalize(a: {:f32, 1}, b: {:f32, 1}, c: {:f32, 1})

      assert Enum.map(attributes, & &1.index) == [0, 1, 2]
    end

    test "handles mixed component types and counts" do
      # The :line layout: two vec2 and a scalar.
      {attributes, stride} =
        VertexLayout.normalize(
          a_position: {:f32, 2},
          a_neighbor: {:f32, 2},
          a_side: {:f32, 1}
        )

      assert stride == 20
      assert Enum.map(attributes, & &1.offset) == [0, 8, 16]
    end

    test "handles narrow types" do
      {attributes, stride} =
        VertexLayout.normalize(colour: {:u8, 4}, id: {:u16, 1}, position: {:f32, 3})

      assert stride == 4 + 2 + 12
      assert Enum.map(attributes, & &1.offset) == [0, 4, 6]
      assert Enum.map(attributes, & &1.type) == [:unsigned_byte, :unsigned_short, :float]
    end

    test "an empty declaration has zero stride" do
      assert {[], 0} = VertexLayout.normalize([])
    end

    test "rejects duplicate attribute names" do
      assert_raise ArgumentError, ~r/duplicate vertex attributes/, fn ->
        VertexLayout.normalize(a_position: {:f32, 2}, a_position: {:f32, 2})
      end
    end

    test "rejects an unsupported component type" do
      assert_raise ArgumentError, ~r/unsupported vertex attribute type/, fn ->
        VertexLayout.normalize(a: {:f64, 2})
      end
    end
  end
end

defmodule WxMVU.GLCanvas.Draw.ColormapTest do
  use ExUnit.Case, async: true

  alias WxMVU.GLCanvas.Draw.Colormap

  describe "data/1" do
    test "produces a 256-entry RGB8 table" do
      data = Colormap.data(:viridis)
      assert byte_size(data) == 256 * 3
    end

    test "every built-in map generates" do
      for name <- Colormap.names() do
        assert byte_size(Colormap.data(name)) == 768, "#{name} generated the wrong size"
      end
    end

    test "the endpoints are the declared stops" do
      data = Colormap.data(:viridis)
      <<first_r, first_g, first_b, _::binary>> = data
      last = binary_part(data, 765, 3)

      assert {first_r, first_g, first_b} == {68, 1, 84}
      assert last == <<253, 231, 37>>
    end

    test "grayscale is monotonic and spans the full range" do
      values =
        for <<r, _g, _b <- Colormap.data(:grayscale)>>, do: r

      assert List.first(values) == 0
      assert List.last(values) == 255
      assert values == Enum.sort(values)
    end

    test "accepts explicit stops" do
      data = Colormap.data([{0.0, {255, 0, 0}}, {1.0, {0, 0, 255}}])

      assert binary_part(data, 0, 3) == <<255, 0, 0>>
      assert binary_part(data, 765, 3) == <<0, 0, 255>>
    end
  end

  describe "sample/2" do
    @ramp [{0.0, {0, 0, 0}}, {1.0, {100, 200, 40}}]

    test "returns the endpoints exactly" do
      assert Colormap.sample(@ramp, 0.0) == {0, 0, 0}
      assert Colormap.sample(@ramp, 1.0) == {100, 200, 40}
    end

    test "interpolates linearly between stops" do
      assert Colormap.sample(@ramp, 0.5) == {50, 100, 20}
    end

    test "clamps outside the range rather than extrapolating" do
      assert Colormap.sample(@ramp, -1.0) == {0, 0, 0}
      assert Colormap.sample(@ramp, 2.0) == {100, 200, 40}
    end

    test "picks the right segment with unevenly spaced stops" do
      stops = [{0.0, {0, 0, 0}}, {0.25, {40, 0, 0}}, {1.0, {40, 0, 255}}]

      assert Colormap.sample(stops, 0.25) == {40, 0, 0}
      # Halfway along the second, much longer segment.
      assert Colormap.sample(stops, 0.625) == {40, 0, 128}
    end
  end

  describe "validation" do
    test "rejects a single stop" do
      assert_raise ArgumentError, ~r/at least two stops/, fn ->
        Colormap.data([{0.0, {0, 0, 0}}])
      end
    end

    test "rejects out-of-order stops" do
      assert_raise ArgumentError, ~r/strictly increasing/, fn ->
        Colormap.data([{0.0, {0, 0, 0}}, {1.0, {1, 1, 1}}, {0.5, {2, 2, 2}}])
      end
    end

    test "rejects duplicate positions, which would divide by zero" do
      assert_raise ArgumentError, ~r/strictly increasing/, fn ->
        Colormap.data([{0.0, {0, 0, 0}}, {0.5, {1, 1, 1}}, {0.5, {2, 2, 2}}])
      end
    end

    test "rejects an unknown name, listing the known ones" do
      assert_raise ArgumentError, ~r/unknown colormap :nope/, fn ->
        Colormap.stops(:nope)
      end
    end
  end
end
