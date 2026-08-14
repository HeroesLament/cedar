defmodule Cedar.Visual.ViewportTest do
  @moduledoc """
  The viewport under a real OpenGL context.

  The properties worth asserting here are the ones a screenshot would not tell
  you apart: that several objects share one camera, that moving something does
  not re-upload it, and that the depth buffer actually orders them.
  """

  use Cedar.GLCase

  alias Cedar.{Camera, Math}
  alias Cedar.Visual.{Mesh, Viewport}

  @size 48

  setup do
    fbo = offscreen(@size, depth: true)
    %{fbo: fbo}
  end

  defp frame(size) do
    %Cedar.Visual.Frame{
      pixel_size: {size, size},
      logical_size: {size, size},
      dpi_scale: 1.0
    }
  end

  defp render(state) do
    clear()
    GL.clear(:depth)
    {:ok, state} = Viewport.draw(state, frame(@size))
    state
  end

  defp lit, do: Enum.count(red_channel(@size), &(&1 > 8))

  defp part(id, opts \\ []) do
    %{
      id: id,
      mesh: Keyword.get(opts, :mesh, Mesh.box(1.0)),
      transform: Keyword.get(opts, :transform, Math.identity()),
      color: Keyword.get(opts, :color, {1.0, 0.2, 0.2, 1.0})
    }
  end

  defp camera(opts \\ []) do
    Camera.new(Keyword.merge([target: {0.0, 0.0, 0.0}, distance: 4.0], opts))
  end

  describe "drawing" do
    test "an empty scene draws nothing" do
      {:ok, state} = Viewport.init(%{}, camera: camera())

      state = render(state)
      assert lit() == 0

      Viewport.destroy(state)
    end

    test "a node appears" do
      {:ok, state} = Viewport.init(%{}, camera: camera(), nodes: [part(:box)])

      state = render(state)
      count = lit()

      assert count > 0, "nothing rendered"
      assert count < @size * @size, "the box filled the frame"

      Viewport.destroy(state)
    end

    test "several nodes share one camera" do
      # The whole reason this exists. Two boxes placed apart must both be
      # visible from a single eye position - as separate :mesh layers each
      # would carry its own camera and they could disagree.
      left = part(:left, transform: Math.translation({-1.2, 0.0, 0.0}))
      right = part(:right, transform: Math.translation({1.2, 0.0, 0.0}))

      {:ok, state} =
        Viewport.init(%{},
          camera: camera(distance: 6.0, yaw: 0.0, pitch: 0.0),
          nodes: [left, right]
        )

      state = render(state)

      row = for col <- 0..(@size - 1), do: elem(pixel(@size, col, div(@size, 2)), 0)
      left_half = row |> Enum.take(div(@size, 2)) |> Enum.count(&(&1 > 8))
      right_half = row |> Enum.drop(div(@size, 2)) |> Enum.count(&(&1 > 8))

      assert left_half > 0, "nothing on the left"
      assert right_half > 0, "nothing on the right"

      Viewport.destroy(state)
    end

    test "depth orders overlapping nodes" do
      # A near red box and a far green one on the same axis: the near one wins
      # every contested pixel, which only happens if depth is on and cleared.
      near =
        part(:near, transform: Math.translation({0.0, 0.0, 1.0}), color: {1.0, 0.0, 0.0, 1.0})

      far = part(:far, transform: Math.translation({0.0, 0.0, -1.0}), color: {0.0, 1.0, 0.0, 1.0})

      {:ok, state} =
        Viewport.init(%{},
          camera: camera(distance: 8.0, yaw: 0.0, pitch: 0.0),
          nodes: [far, near]
        )

      state = render(state)
      {r, g, _b} = pixel(@size, div(@size, 2), div(@size, 2))

      assert r > g, "the far box drew over the near one (#{r} vs #{g})"

      Viewport.destroy(state)
    end

    test "declaration order does not decide occlusion" do
      # Same scene, nodes listed the other way round. If painting order decided
      # it, this would flip.
      near =
        part(:near, transform: Math.translation({0.0, 0.0, 1.0}), color: {1.0, 0.0, 0.0, 1.0})

      far = part(:far, transform: Math.translation({0.0, 0.0, -1.0}), color: {0.0, 1.0, 0.0, 1.0})

      {:ok, state} =
        Viewport.init(%{},
          camera: camera(distance: 8.0, yaw: 0.0, pitch: 0.0),
          nodes: [near, far]
        )

      state = render(state)
      {r, g, _b} = pixel(@size, div(@size, 2), div(@size, 2))

      assert r > g

      Viewport.destroy(state)
    end
  end

  describe "the camera" do
    test "orbiting changes the image without touching the nodes" do
      {:ok, state} = Viewport.init(%{}, camera: camera(yaw: 0.0), nodes: [part(:box)])

      state = render(state)
      before = red_channel(@size)

      {:ok, state} = Viewport.update(state, camera: camera(yaw: 55.0))
      state = render(state)

      refute red_channel(@size) == before
      assert Viewport.nodes(state) |> length() == 1

      Viewport.destroy(state)
    end

    test "backing off shrinks what is drawn" do
      {:ok, state} = Viewport.init(%{}, camera: camera(distance: 3.0), nodes: [part(:box)])

      state = render(state)
      near = lit()

      {:ok, state} = Viewport.update(state, camera: camera(distance: 12.0))
      state = render(state)
      far = lit()

      assert far < near, "#{near} -> #{far}"
      assert far > 0, "the box vanished"

      Viewport.destroy(state)
    end

    test "a camera may be sent as data for a high-rate control" do
      {:ok, state} = Viewport.init(%{}, camera: camera(distance: 3.0), nodes: [part(:box)])
      state = render(state)
      near = lit()

      {:ok, state} = Viewport.handle_data(state, {:camera, camera(distance: 12.0)})
      state = render(state)

      assert lit() < near

      Viewport.destroy(state)
    end

    test "accepts a keyword list as well as a struct" do
      {:ok, state} = Viewport.init(%{}, camera: [distance: 5.0], nodes: [part(:box)])

      assert %Camera{distance: 5.0} = state.camera

      Viewport.destroy(state)
    end
  end

  describe "node reconciliation" do
    test "moving a node reuses its geometry" do
      # The property that makes driving this from forward kinematics viable: a
      # pose change must be a uniform write, not an upload. Identity of the
      # cached geometry record is the observable proxy.
      {:ok, state} = Viewport.init(%{}, camera: camera(), nodes: [part(:arm)])
      %{geometry: before} = state.cache[:arm]

      {:ok, state} =
        Viewport.update(state, nodes: [part(:arm, transform: Math.translation({0.5, 0.0, 0.0}))])

      assert state.cache[:arm].geometry == before

      Viewport.destroy(state)
    end

    test "changing a node's mesh replaces its geometry" do
      {:ok, state} =
        Viewport.init(%{}, camera: camera(), nodes: [part(:arm, mesh: Mesh.box(1.0))])

      {:ok, state} = Viewport.update(state, nodes: [part(:arm, mesh: Mesh.box(2.0))])

      assert state.cache[:arm].mesh == Mesh.box(2.0)

      Viewport.destroy(state)
    end

    test "a removed node releases its geometry" do
      {:ok, state} =
        Viewport.init(%{}, camera: camera(), nodes: [part(:a), part(:b)])

      assert map_size(state.cache) == 2

      {:ok, state} = Viewport.update(state, nodes: [part(:a)])

      assert map_size(state.cache) == 1
      assert Map.has_key?(state.cache, :a)

      Viewport.destroy(state)
    end

    test "clearing empties the scene" do
      {:ok, state} = Viewport.init(%{}, camera: camera(), nodes: [part(:box)])
      {:ok, state} = Viewport.handle_data(state, :clear)

      state = render(state)

      assert lit() == 0
      assert state.cache == %{}

      Viewport.destroy(state)
    end

    test "nodes can be sent rather than declared" do
      {:ok, state} = Viewport.init(%{}, camera: camera())
      {:ok, state} = Viewport.handle_data(state, {:nodes, [part(:box)]})

      state = render(state)

      assert lit() > 0

      Viewport.destroy(state)
    end

    test "an unrelated update leaves the scene alone" do
      # A camera change must not be read as "no nodes declared, so no nodes".
      {:ok, state} = Viewport.init(%{}, camera: camera(), nodes: [part(:box)])
      {:ok, state} = Viewport.update(state, camera: camera(yaw: 10.0))

      state = render(state)

      assert lit() > 0

      Viewport.destroy(state)
    end

    test "a malformed node says what one looks like" do
      {:ok, state} = Viewport.init(%{}, camera: camera())

      assert_raise ArgumentError, ~r/%\{id: id, mesh: mesh/, fn ->
        Viewport.update(state, nodes: [%{id: :bad}])
      end

      Viewport.destroy(state)
    end

    test "transform and colour have defaults" do
      {:ok, state} = Viewport.init(%{}, camera: camera(), nodes: [%{id: :x, mesh: Mesh.box(1.0)}])

      [item] = Viewport.nodes(state)

      assert item.transform == Math.identity()
      assert is_tuple(item.color)

      Viewport.destroy(state)
    end
  end

  describe "a posed chain" do
    test "renders a stack of links at their own transforms" do
      # The shape of the real thing: several links, one camera, each placed by
      # its own matrix as forward kinematics would hand them over.
      links =
        for {i, y} <- Enum.with_index([0.0, 0.45, 0.9]) |> Enum.map(fn {y, i} -> {i, y} end) do
          %{
            id: :"link#{i}",
            mesh: Mesh.box({0.35, 0.4, 0.35}),
            transform: Math.translation({0.0, y, 0.0}),
            color: {0.9, 0.6, 0.2, 1.0}
          }
        end

      {:ok, state} =
        Viewport.init(%{},
          camera: camera(distance: 3.5, yaw: 0.0, pitch: 0.0, target: {0.0, 0.45, 0.0}),
          nodes: links
        )

      state = render(state)

      column = for row <- 0..(@size - 1), do: elem(pixel(@size, div(@size, 2), row), 0)
      covered = Enum.count(column, &(&1 > 8))

      # A three-link tower is tall and narrow: it should cover much of the
      # centre column and nothing like all of the frame.
      assert covered > @size / 3, "the tower is too short (#{covered} of #{@size})"
      assert lit() < @size * @size * 0.6, "it filled the frame"

      Viewport.destroy(state)
    end
  end
end
