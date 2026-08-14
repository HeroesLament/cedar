defmodule Cedar.CameraTest do
  @moduledoc """
  The orbit camera, tested on what it does rather than on what it stores.
  """

  use ExUnit.Case, async: true

  alias Cedar.{Camera, Math}

  defp close?(a, b, tolerance \\ 1.0e-6), do: abs(a - b) <= tolerance

  defp distance_to_target(camera) do
    Math.length(Math.sub(Camera.eye(camera), camera.target))
  end

  describe "eye/1" do
    test "sits at the orbit distance from the target" do
      camera = Camera.new(target: {1.0, 2.0, 3.0}, distance: 5.0)

      assert close?(distance_to_target(camera), 5.0, 1.0e-9)
    end

    test "pitch raises it above the target" do
      level = Camera.new(pitch: 0.0)
      above = Camera.new(pitch: 45.0)

      {_, level_y, _} = Camera.eye(level)
      {_, above_y, _} = Camera.eye(above)

      assert above_y > level_y
    end

    test "yaw rotates it around the up axis without changing height" do
      a = Camera.new(yaw: 0.0, pitch: 20.0)
      b = Camera.new(yaw: 90.0, pitch: 20.0)

      {_, ay, _} = Camera.eye(a)
      {_, by, _} = Camera.eye(b)

      assert close?(ay, by)
      refute Camera.eye(a) == Camera.eye(b)
    end
  end

  describe "orbit/3" do
    test "changes the angle and nothing else" do
      before = Camera.new(distance: 3.0, target: {1.0, 0.0, 0.0})
      after_drag = Camera.orbit(before, 30.0, 10.0)

      assert after_drag.target == before.target
      assert after_drag.distance == before.distance
      assert close?(distance_to_target(after_drag), 3.0, 1.0e-9)
    end

    test "pitch is clamped short of vertical" do
      # At exactly 90 the view direction is parallel to up, look_at cannot
      # establish handedness, and the view flips. This clamp is the difference
      # between a camera that feels solid and one that snaps.
      camera = Camera.new() |> Camera.orbit(0.0, 1000.0)

      assert camera.pitch < 90.0
      assert camera.pitch > 88.0

      down = Camera.new() |> Camera.orbit(0.0, -1000.0)
      assert down.pitch > -90.0
    end

    test "the view matrix stays valid at the pitch limit" do
      camera = Camera.new() |> Camera.orbit(0.0, 1000.0)

      refute Camera.view(camera) == Math.identity()
    end

    test "yaw wraps rather than accumulating forever" do
      camera = Enum.reduce(1..20, Camera.new(yaw: 0.0), fn _, c -> Camera.orbit(c, 90.0, 0.0) end)

      assert camera.yaw >= 0.0 and camera.yaw < 360.0
    end
  end

  describe "dolly/2" do
    test "scales the distance" do
      camera = Camera.new(distance: 4.0) |> Camera.dolly(0.5)

      assert close?(camera.distance, 2.0)
    end

    test "never reaches zero" do
      # A distance of zero puts the eye on the target and the view matrix
      # degenerates.
      camera = Enum.reduce(1..500, Camera.new(distance: 4.0), fn _, c -> Camera.dolly(c, 0.5) end)

      assert camera.distance > 0.0
      refute Camera.view(camera) == Math.identity()
    end

    test "leaves the target alone" do
      camera = Camera.new(target: {1.0, 2.0, 3.0}) |> Camera.dolly(2.0)

      assert camera.target == {1.0, 2.0, 3.0}
    end
  end

  describe "pan/3" do
    test "moves the target across the view plane" do
      before = Camera.new()
      after_pan = Camera.pan(before, 1.0, 0.0)

      refute after_pan.target == before.target
      assert close?(after_pan.distance, before.distance)
    end

    test "panning right then left returns to where it started" do
      camera = Camera.new(target: {0.5, 0.5, 0.5})
      round_trip = camera |> Camera.pan(1.0, 0.5) |> Camera.pan(-1.0, -0.5)

      {ax, ay, az} = camera.target
      {bx, by, bz} = round_trip.target

      assert close?(ax, bx) and close?(ay, by) and close?(az, bz)
    end

    test "pans in the view plane, not the world plane" do
      # Panning right from a rotated camera must move the target along the
      # camera's right, not along world X - otherwise dragging feels like it
      # disobeys the mouse as soon as you orbit.
      rotated = Camera.new(yaw: 90.0)
      {x, _y, z} = Camera.pan(rotated, 1.0, 0.0).target

      assert abs(z) > abs(x)
    end
  end

  describe "fit/4" do
    test "centres the target on the box" do
      camera = Camera.fit(Camera.new(), {-1.0, 0.0, -1.0}, {1.0, 2.0, 1.0})

      assert camera.target == {0.0, 1.0, 0.0}
    end

    test "a bigger box means a bigger distance" do
      small = Camera.fit(Camera.new(), {-0.1, -0.1, -0.1}, {0.1, 0.1, 0.1})
      large = Camera.fit(Camera.new(), {-5.0, -5.0, -5.0}, {5.0, 5.0, 5.0})

      assert large.distance > small.distance
    end

    test "a degenerate box does not divide by zero" do
      # A cell containing one point, or one flat plate.
      camera = Camera.fit(Camera.new(), {1.0, 1.0, 1.0}, {1.0, 1.0, 1.0})

      assert camera.distance > 0.0
      assert is_float(camera.distance)
    end
  end

  describe "look/2" do
    test "standard views keep what you are looking at" do
      camera = Camera.new(target: {1.0, 2.0, 3.0}, distance: 7.0)
      top = Camera.look(camera, :top)

      assert top.target == {1.0, 2.0, 3.0}
      assert close?(top.distance, 7.0)
    end

    test "top looks down and front looks level" do
      {_, top_y, _} = Camera.eye(Camera.look(Camera.new(), :top))
      {_, front_y, _} = Camera.eye(Camera.look(Camera.new(), :front))

      assert top_y > front_y
      assert close?(front_y, 0.0, 1.0e-9)
    end

    test "top is clamped like any other pitch" do
      assert Camera.look(Camera.new(), :top).pitch < 90.0
    end

    test "an unknown view lists the real ones" do
      assert_raise ArgumentError, ~r/:top, :bottom, :front/, fn ->
        Camera.look(Camera.new(), :sideways)
      end
    end
  end

  describe "view_projection/2" do
    test "is projection times view" do
      camera = Camera.new()
      expected = Math.multiply(Camera.projection(camera, 1.5), Camera.view(camera))

      assert Camera.view_projection(camera, 1.5) == expected
    end

    test "puts the target in front of the camera" do
      camera = Camera.new(target: {0.0, 0.0, 0.0}, distance: 5.0)
      {_x, _y, z} = Math.transform_point(Camera.view(camera), camera.target)

      # Down -Z, at the orbit distance.
      assert close?(z, -5.0, 1.0e-6)
    end

    test "a target at the centre projects to the middle of the screen" do
      camera = Camera.new(target: {2.0, 1.0, -3.0})
      {x, y, _z} = Math.transform_point(Camera.view_projection(camera, 1.6), camera.target)

      assert close?(x, 0.0, 1.0e-6)
      assert close?(y, 0.0, 1.0e-6)
    end
  end
end
