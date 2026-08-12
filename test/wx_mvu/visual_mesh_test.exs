defmodule WxMVU.Visual.MeshTest do
  @moduledoc """
  Mesh construction, tested without a GL context.

  `build/1` is where a mesh stops being a list of tuples and becomes bytes the
  driver will read blind: an index one past the end is undefined behaviour in
  OpenGL rather than an error, so the checks have to happen here.
  """

  use ExUnit.Case, async: true

  alias WxMVU.Math
  alias WxMVU.Visual.Mesh

  # position (3) + normal (3), all f32
  @stride 24

  defp unpack(binary) do
    for <<px::float-32-native, py::float-32-native, pz::float-32-native, nx::float-32-native,
          ny::float-32-native, nz::float-32-native <- binary>> do
      %{position: {px, py, pz}, normal: {nx, ny, nz}}
    end
  end

  defp indices(binary) do
    for <<i::unsigned-integer-32-native <- binary>>, do: i
  end

  defp close?(a, b, tolerance \\ 1.0e-5), do: abs(a - b) <= tolerance

  describe "build/1" do
    test "no mesh is two empty binaries, not a crash" do
      assert Mesh.build(nil) == {<<>>, <<>>}
      assert Mesh.build(%{positions: [], indices: []}) == {<<>>, <<>>}
    end

    test "interleaves position and normal per vertex" do
      mesh = %{
        positions: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}],
        normals: List.duplicate({0.0, 0.0, 1.0}, 3),
        indices: [{0, 1, 2}]
      }

      {vertices, index_binary} = Mesh.build(mesh)

      assert byte_size(vertices) == 3 * @stride
      assert indices(index_binary) == [0, 1, 2]

      [first | _] = unpack(vertices)
      assert first.position == {0.0, 0.0, 0.0}
      assert first.normal == {0.0, 0.0, 1.0}
    end

    test "an out-of-range index is refused" do
      mesh = %{positions: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}], indices: [{0, 1, 2}]}

      assert_raise ArgumentError, ~r/index 2 is out of range for 2 vertices/, fn ->
        Mesh.build(mesh)
      end
    end

    test "a normal count that disagrees with the positions is refused" do
      mesh = %{
        positions: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}],
        normals: [{0.0, 0.0, 1.0}],
        indices: [{0, 1, 2}]
      }

      assert_raise ArgumentError, ~r/3 positions but 1 normals/, fn -> Mesh.build(mesh) end
    end

    test "something that is not a mesh says what one looks like" do
      assert_raise ArgumentError, ~r/%\{positions:/, fn -> Mesh.build(%{verts: []}) end
    end

    test "accepts integer coordinates" do
      mesh = %{positions: [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}], indices: [{0, 1, 2}]}
      {vertices, _} = Mesh.build(mesh)

      [first | _] = unpack(vertices)
      assert first.position == {0.0, 0.0, 0.0}
    end
  end

  describe "smooth_normals/2" do
    test "a single triangle gives all three vertices its face normal" do
      positions = [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}]
      normals = Mesh.smooth_normals(positions, [{0, 1, 2}])

      assert Enum.all?(normals, fn {x, y, z} ->
               close?(x, 0.0) and close?(y, 0.0) and close?(z, 1.0)
             end)
    end

    test "winding order determines which way normals point" do
      positions = [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}]

      [{_, _, forward} | _] = Mesh.smooth_normals(positions, [{0, 1, 2}])
      [{_, _, backward} | _] = Mesh.smooth_normals(positions, [{0, 2, 1}])

      assert close?(forward, 1.0)
      assert close?(backward, -1.0)
    end

    test "a shared vertex averages the faces meeting at it" do
      # Two triangles at right angles sharing an edge: the shared vertices
      # should point diagonally between the two faces.
      positions = [
        {0.0, 0.0, 0.0},
        {1.0, 0.0, 0.0},
        {0.0, 1.0, 0.0},
        {0.0, 0.0, -1.0}
      ]

      normals = Mesh.smooth_normals(positions, [{0, 1, 2}, {0, 2, 3}])
      shared = Enum.at(normals, 0)

      assert close?(Math.length(shared), 1.0)
      # Not aligned with either face normal.
      {_x, _y, z} = shared
      assert z > 0.0 and z < 1.0
    end

    test "an unreferenced vertex gets a zero normal rather than NaN" do
      positions = [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {5.0, 5.0, 5.0}]
      normals = Mesh.smooth_normals(positions, [{0, 1, 2}])

      assert Enum.at(normals, 3) == {0.0, 0.0, 0.0}
    end

    test "area weighting stops slivers outvoting real faces" do
      # A large face in the XY plane and a tiny one tilted away, sharing v0.
      # Averaging unit face normals would let the sliver pull the result far
      # more than its area justifies.
      positions = [
        {0.0, 0.0, 0.0},
        {10.0, 0.0, 0.0},
        {0.0, 10.0, 0.0},
        {0.001, 0.0, 0.001}
      ]

      [{_x, _y, z} | _] = Mesh.smooth_normals(positions, [{0, 1, 2}, {0, 1, 3}])

      assert z > 0.99
    end
  end

  describe "box/1" do
    test "six faces of four vertices, two triangles each" do
      %{positions: positions, normals: normals, indices: indices} = Mesh.box(2.0)

      assert length(positions) == 24
      assert length(normals) == 24
      assert length(indices) == 12
    end

    test "faces do not share vertices, so edges stay hard" do
      %{normals: normals} = Mesh.box(1.0)

      assert normals |> Enum.uniq() |> length() == 6
    end

    test "every index is in range" do
      %{positions: positions, indices: indices} = Mesh.box(1.0)
      count = length(positions)

      assert Enum.all?(indices, fn {a, b, c} ->
               Enum.all?([a, b, c], &(&1 >= 0 and &1 < count))
             end)
    end

    test "it is centred on the origin" do
      %{positions: positions} = Mesh.box(4.0)
      xs = Enum.map(positions, &elem(&1, 0))

      assert Enum.min(xs) == -2.0
      assert Enum.max(xs) == 2.0
    end

    test "a non-uniform box is a box" do
      %{positions: positions} = Mesh.box({2.0, 4.0, 6.0})

      assert positions |> Enum.map(&elem(&1, 1)) |> Enum.max() == 2.0
      assert positions |> Enum.map(&elem(&1, 2)) |> Enum.max() == 3.0
    end

    test "the computed normals agree with the declared ones" do
      # The declared per-face normals and the winding order have to tell the
      # same story, or the box lights inside-out.
      %{positions: positions, normals: declared, indices: indices} = Mesh.box(1.0)
      computed = Mesh.smooth_normals(positions, indices)

      assert Enum.zip(declared, computed)
             |> Enum.all?(fn {{dx, dy, dz}, {cx, cy, cz}} ->
               close?(dx, cx) and close?(dy, cy) and close?(dz, cz)
             end)
    end
  end

  describe "plane/2" do
    test "one division is two triangles" do
      %{positions: positions, indices: indices} = Mesh.plane(1.0)

      assert length(positions) == 4
      assert length(indices) == 2
    end

    test "divisions grow the grid quadratically" do
      %{positions: positions, indices: indices} = Mesh.plane(1.0, 4)

      assert length(positions) == 25
      assert length(indices) == 32
    end

    test "it faces up" do
      %{normals: normals} = Mesh.plane(1.0, 3)

      assert Enum.uniq(normals) == [{0.0, 1.0, 0.0}]
    end

    test "the winding agrees with the declared up normal" do
      %{positions: positions, indices: indices} = Mesh.plane(2.0, 2)
      [{_x, y, _z} | _] = Mesh.smooth_normals(positions, indices)

      assert close?(y, 1.0)
    end

    test "it builds" do
      {vertices, index_binary} = Mesh.build(Mesh.plane(1.0, 2))

      assert byte_size(vertices) == 9 * @stride
      assert length(indices(index_binary)) == 24
    end
  end
end
