defmodule Cedar.MathTest do
  @moduledoc """
  The linear algebra, checked against results worked out independently.

  Matrix code is uniquely bad at failing loudly — a transposed matrix renders
  *something*, a wrong handedness renders the back of the model, and both look
  plausible until a second object appears. So these tests assert on transformed
  points rather than on matrix entries wherever they can: a point is a claim
  about what the matrix does, an entry is only a claim about what it contains.
  """

  use ExUnit.Case, async: true

  alias Cedar.Math

  defp close?(a, b, tolerance \\ 1.0e-5), do: abs(a - b) <= tolerance

  defp close_point?({ax, ay, az}, {bx, by, bz}, tolerance \\ 1.0e-5) do
    close?(ax, bx, tolerance) and close?(ay, by, tolerance) and close?(az, bz, tolerance)
  end

  describe "vectors" do
    test "cross products are right-handed" do
      assert Math.cross({1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}) == {0.0, 0.0, 1.0}
      assert Math.cross({0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}) == {1.0, 0.0, 0.0}
    end

    test "normalize returns zero rather than NaN for a zero vector" do
      assert Math.normalize({0.0, 0.0, 0.0}) == {0.0, 0.0, 0.0}
    end

    test "normalize preserves direction" do
      {x, y, z} = Math.normalize({3.0, 4.0, 0.0})
      assert close?(x, 0.6)
      assert close?(y, 0.8)
      assert close?(z, 0.0)
    end
  end

  describe "multiply/2" do
    test "identity is the identity" do
      m = Math.translation({1.0, 2.0, 3.0})

      assert Math.multiply(m, Math.identity()) == m
      assert Math.multiply(Math.identity(), m) == m
    end

    test "the right operand applies first" do
      # Scale then translate: the translation must NOT be scaled.
      m = Math.multiply(Math.translation({10.0, 0.0, 0.0}), Math.scaling(2.0))

      assert close_point?(Math.transform_point(m, {1.0, 0.0, 0.0}), {12.0, 0.0, 0.0})
    end

    test "the other order scales the translation" do
      m = Math.multiply(Math.scaling(2.0), Math.translation({10.0, 0.0, 0.0}))

      assert close_point?(Math.transform_point(m, {1.0, 0.0, 0.0}), {22.0, 0.0, 0.0})
    end

    test "the list form composes left to right" do
      a = Math.translation({1.0, 0.0, 0.0})
      b = Math.scaling(2.0)
      c = Math.rotation_z(90.0)

      assert Math.multiply([a, b, c]) == Math.multiply(a, Math.multiply(b, c))
    end
  end

  describe "rotation" do
    test "90 degrees about Z takes +X to +Y" do
      m = Math.rotation_z(90.0)

      assert close_point?(Math.transform_point(m, {1.0, 0.0, 0.0}), {0.0, 1.0, 0.0})
    end

    test "90 degrees about Y takes +Z to +X" do
      m = Math.rotation_y(90.0)

      assert close_point?(Math.transform_point(m, {0.0, 0.0, 1.0}), {1.0, 0.0, 0.0})
    end

    test "four quarter turns is the identity" do
      quarter = Math.rotation({1.0, 2.0, 3.0}, 90.0)
      full = Math.multiply([quarter, quarter, quarter, quarter])

      assert close_point?(Math.transform_point(full, {1.0, -2.0, 0.5}), {1.0, -2.0, 0.5})
    end

    test "a zero axis is the identity, not NaN" do
      assert Math.rotation({0.0, 0.0, 0.0}, 45.0) == Math.identity()
    end
  end

  describe "perspective/4" do
    test "a point on the near plane maps to -1 depth and the far plane to +1" do
      m = Math.perspective(45.0, 1.0, 1.0, 10.0)

      {_x, _y, near_z} = Math.transform_point(m, {0.0, 0.0, -1.0})
      {_x2, _y2, far_z} = Math.transform_point(m, {0.0, 0.0, -10.0})

      assert close?(near_z, -1.0, 1.0e-4)
      assert close?(far_z, 1.0, 1.0e-4)
    end

    test "aspect ratio squeezes X, not Y" do
      wide = Math.perspective(45.0, 2.0, 0.1, 100.0)
      square = Math.perspective(45.0, 1.0, 0.1, 100.0)

      {wx, wy, _} = Math.transform_point(wide, {1.0, 1.0, -5.0})
      {sx, sy, _} = Math.transform_point(square, {1.0, 1.0, -5.0})

      assert close?(wx, sx / 2.0)
      assert close?(wy, sy)
    end

    test "the top of the frustum lands on the top of clip space" do
      # At distance d, a 90-degree vertical FOV puts y = d exactly on the edge.
      m = Math.perspective(90.0, 1.0, 0.1, 100.0)

      {_x, y, _z} = Math.transform_point(m, {0.0, 5.0, -5.0})

      assert close?(y, 1.0, 1.0e-4)
    end

    test "a degenerate frustum is refused rather than producing infinities" do
      assert_raise ArgumentError, ~r/far > near/, fn ->
        Math.perspective(45.0, 1.0, 10.0, 1.0)
      end

      assert_raise ArgumentError, ~r/aspect > 0/, fn ->
        Math.perspective(45.0, 0.0, 0.1, 100.0)
      end
    end
  end

  describe "look_at/3" do
    test "the target lands on the view axis, at its distance" do
      # Not at the origin - the origin of view space is the *camera*. The
      # target sits straight ahead down -Z, exactly as far away as it is in
      # world space.
      eye = {4.0, 5.0, 6.0}
      target = {1.0, 2.0, 3.0}
      view = Math.look_at(eye, target)

      distance = Math.length(Math.sub(target, eye))

      assert close_point?(Math.transform_point(view, target), {0.0, 0.0, -distance})
      assert close_point?(Math.transform_point(view, eye), {0.0, 0.0, 0.0})
    end

    test "the camera looks down -Z" do
      view = Math.look_at({0.0, 0.0, 10.0}, {0.0, 0.0, 0.0})

      {_x, _y, z} = Math.transform_point(view, {0.0, 0.0, 0.0})

      assert close?(z, -10.0)
    end

    test "distance is preserved" do
      view = Math.look_at({3.0, 3.0, 3.0}, {0.0, 0.0, 0.0})
      {x, y, z} = Math.transform_point(view, {0.0, 0.0, 0.0})

      assert close?(:math.sqrt(x * x + y * y + z * z), :math.sqrt(27.0))
    end

    test "an up vector parallel to the view yields the identity, not NaN" do
      view = Math.look_at({0.0, 5.0, 0.0}, {0.0, 0.0, 0.0}, {0.0, 1.0, 0.0})

      assert view == Math.identity()
    end
  end

  describe "normal_matrix/1" do
    test "a rigid transform leaves normals alone" do
      # Rotation is its own inverse transpose, so the normal matrix is just the
      # rotation back again.
      model = Math.rotation_y(30.0)
      n = Math.normal_matrix(model)

      [m00, m01, m02, _, m10, m11, m12, _, m20, m21, m22, _ | _] = model

      assert Enum.zip(n, [m00, m01, m02, m10, m11, m12, m20, m21, m22])
             |> Enum.all?(fn {a, b} -> close?(a, b) end)
    end

    test "a non-uniform scale inverts, which is the whole point" do
      # Squash Y by half: a normal along Y must get *longer*, not shorter,
      # or the lighting tilts the wrong way across the squashed surface.
      model = Math.scaling({1.0, 0.5, 1.0})
      [_, _, _, _, m11, _, _, _, _] = Math.normal_matrix(model)

      assert close?(m11, 2.0)
    end

    test "a singular model matrix yields the identity rather than infinities" do
      model = Math.scaling({1.0, 0.0, 1.0})

      assert Math.normal_matrix(model) == [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    end

    test "it is nine floats, which is what a :mat3 field wants" do
      assert length(Math.normal_matrix(Math.identity())) == 9
    end
  end

  describe "orthographic/6" do
    test "the box corners map to the clip cube" do
      m = Math.orthographic(-2.0, 2.0, -1.0, 1.0, 0.1, 10.0)

      assert close_point?(Math.transform_point(m, {2.0, 1.0, -0.1}), {1.0, 1.0, -1.0})
      assert close_point?(Math.transform_point(m, {-2.0, -1.0, -10.0}), {-1.0, -1.0, 1.0})
    end
  end
end
