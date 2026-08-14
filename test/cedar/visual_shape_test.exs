defmodule Cedar.VisualShapeTest do
  @moduledoc """
  Host-side behaviour of the `:shape` visual.

  Everything here runs without a GL context, because everything here is the
  part that decides *what* to draw rather than the part that draws it. The
  distance functions themselves are tested in `cedar-shader-core` on stable
  Rust; the pixels are tested by the golden suite.

  The properties worth pinning are the ones whose failure is invisible until
  something renders mirrored, inverted, or one pixel wrong: the angular
  convention, the circle identity, and the radius clamps.
  """

  use ExUnit.Case, async: true

  alias Cedar.Visual.Shape

  describe "wedge/1" do
    # The shader's sector and arc open along +Y and are rotated into place.
    # Getting the rotation transposed produces a shape that is correct in size
    # and wrong in orientation, which no type can catch.

    test "a wedge centred on +X rotates onto +Y" do
      # Mid-angle 0 means the slice points along +X. Rotating it upright is a
      # quarter turn, whose cosine is 0 and sine is 1.
      {cos_r, sin_r, _, _} = Shape.wedge({-0.5, 0.5})

      assert_in_delta cos_r, 0.0, 1.0e-6
      assert_in_delta sin_r, 1.0, 1.0e-6
    end

    test "a wedge already centred on +Y needs no rotation" do
      half_pi = :math.pi() / 2

      {cos_r, sin_r, _, _} = Shape.wedge({half_pi - 0.3, half_pi + 0.3})

      assert_in_delta cos_r, 1.0, 1.0e-6
      assert_in_delta sin_r, 0.0, 1.0e-6
    end

    test "the half aperture is half the span" do
      {_, _, sin_half, cos_half} = Shape.wedge({0.0, :math.pi() / 2})

      quarter = :math.pi() / 4
      assert_in_delta sin_half, :math.sin(quarter), 1.0e-6
      assert_in_delta cos_half, :math.cos(quarter), 1.0e-6
    end

    test "a span wider than a full turn clamps to a half aperture of pi" do
      # Beyond a half turn the wedge is already the whole disc. Letting the
      # half-aperture grow past pi wraps it around and starts cutting the disc
      # away again, so a "more than full" sector would render as a slice.
      {_, _, sin_half, cos_half} = Shape.wedge({0.0, 10.0})

      assert_in_delta sin_half, :math.sin(:math.pi()), 1.0e-6
      assert_in_delta cos_half, :math.cos(:math.pi()), 1.0e-6
    end

    test "a reversed span is the same wedge as a forward one" do
      forward = Shape.wedge({0.5, 1.5})
      reversed = Shape.wedge({1.5, 0.5})

      assert forward == reversed
    end

    test "a zero-width span has zero aperture" do
      {_, _, sin_half, cos_half} = Shape.wedge({1.0, 1.0})

      assert_in_delta sin_half, 0.0, 1.0e-6
      assert_in_delta cos_half, 1.0, 1.0e-6
    end

    test "rejects anything that is not a pair of numbers" do
      assert_raise ArgumentError, ~r/:angles must be/, fn -> Shape.wedge(:full) end
      assert_raise ArgumentError, ~r/:angles must be/, fn -> Shape.wedge({0.0}) end
    end
  end
end
