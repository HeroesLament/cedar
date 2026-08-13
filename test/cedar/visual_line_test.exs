defmodule Cedar.Visual.LineTest do
  @moduledoc """
  The polyline expansion, tested without a GL context.

  This is the part of `:line` that is pure: turning a list of points into the
  vertex stream the shader expects. The shader half is covered by the `:gl`
  render tests.
  """

  use ExUnit.Case, async: true

  alias Cedar.Visual.Line

  # a_position (2) + a_neighbor (2) + a_side (1), all f32
  @stride 20
  @vertices_per_segment 6

  defp unpack(binary) do
    for <<px::float-32-native, py::float-32-native, nx::float-32-native, ny::float-32-native,
          side::float-32-native <- binary>> do
      %{position: {px, py}, neighbor: {nx, ny}, side: side}
    end
  end

  describe "expand/1" do
    test "a line needs two points to exist" do
      assert Line.expand([]) == <<>>
      assert Line.expand([{0.0, 0.0}]) == <<>>
    end

    test "one segment becomes two triangles" do
      binary = Line.expand([{0.0, 0.0}, {1.0, 0.0}])

      assert byte_size(binary) == @vertices_per_segment * @stride
    end

    test "n points become n-1 segments" do
      points = for i <- 0..4, do: {i * 1.0, 0.0}
      binary = Line.expand(points)

      assert byte_size(binary) == 4 * @vertices_per_segment * @stride
    end

    test "both ends of a segment yield the same direction" do
      # The property the shader depends on. It derives its perpendicular from
      # neighbor - position; if the far end pointed back at the near end, the
      # direction would reverse, the offset would flip, and the quad would
      # cross itself into a bowtie.
      [a, b, c, _c2, _b2, d] = unpack(Line.expand([{0.0, 0.0}, {2.0, 1.0}]))

      direction = fn %{position: {px, py}, neighbor: {nx, ny}} -> {nx - px, ny - py} end

      assert direction.(a) == {2.0, 1.0}
      assert direction.(b) == {2.0, 1.0}
      assert direction.(c) == {2.0, 1.0}
      assert direction.(d) == {2.0, 1.0}
    end

    test "each segment offsets to both sides" do
      vertices = unpack(Line.expand([{0.0, 0.0}, {1.0, 0.0}]))
      sides = Enum.map(vertices, & &1.side)

      assert Enum.sort(Enum.uniq(sides)) == [-1.0, 1.0]
      # Two triangles over four distinct corners: one corner appears twice.
      assert length(sides) == 6
    end

    test "the far vertices sit at the segment's end, not beyond it" do
      # The extrapolated point goes in a_neighbor, never in a_position - a
      # vertex placed at the extrapolation would draw the line twice as long.
      vertices = unpack(Line.expand([{0.0, 0.0}, {1.0, 0.0}]))
      positions = vertices |> Enum.map(& &1.position) |> Enum.uniq() |> Enum.sort()

      assert positions == [{0.0, 0.0}, {1.0, 0.0}]
    end

    test "consecutive segments share their joint position" do
      vertices = unpack(Line.expand([{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}]))
      positions = vertices |> Enum.map(& &1.position) |> Enum.uniq() |> Enum.sort()

      assert positions == [{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}]
    end

    test "a repeated point produces a degenerate segment rather than crashing" do
      # Real data does this. The shader's normalize guards the zero-length
      # direction; expansion just has to not blow up producing it.
      binary = Line.expand([{1.0, 1.0}, {1.0, 1.0}, {2.0, 2.0}])

      assert byte_size(binary) == 2 * @vertices_per_segment * @stride
    end

    test "accepts integer coordinates" do
      binary = Line.expand([{0, 0}, {1, 1}])
      assert byte_size(binary) == @vertices_per_segment * @stride

      [first | _] = unpack(binary)
      assert first.position == {0.0, 0.0}
    end
  end
end
