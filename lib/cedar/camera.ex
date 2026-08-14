defmodule Cedar.Camera do
  @moduledoc """
  An orbit camera, as data.

      camera = Cedar.Camera.new(target: {0.0, 0.4, 0.0}, distance: 3.0)
      camera = Cedar.Camera.orbit(camera, dx, dy)

  Held in spherical coordinates around a target rather than as an eye position,
  because that is what the interaction actually is: dragging rotates you around
  the thing you are looking at, the scroll wheel changes how far away you are,
  and the middle button slides the thing you are looking at. Storing an eye
  point instead means reconstructing those three quantities from it on every
  gesture, and accumulating error while you do.

  Pure. A viewport gets one of these from the model and turns it into matrices;
  nothing here touches GL.

  ## Conventions

  Angles in degrees, distances in whatever unit the scene uses. `yaw` rotates
  about the world up axis, `pitch` is the angle above the horizon, and pitch is
  clamped just short of vertical — at exactly 90° the view direction becomes
  parallel to up, `look_at/3` has no way to establish handedness, and the view
  flips. That clamp is the difference between a camera that feels solid and one
  that snaps when you drag too far.
  """

  alias Cedar.Math

  @type t :: %__MODULE__{
          target: Math.vec3(),
          distance: float(),
          yaw: float(),
          pitch: float(),
          up: Math.vec3(),
          fov: float(),
          near: float(),
          far: float()
        }

  defstruct target: {0.0, 0.0, 0.0},
            distance: 4.0,
            yaw: 45.0,
            pitch: 25.0,
            up: {0.0, 1.0, 0.0},
            fov: 45.0,
            near: 0.05,
            far: 500.0

  # Short of vertical. See the moduledoc.
  @pitch_limit 89.0

  @doc "A camera, with any field overridden."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, opts)

  @doc """
  Rotates around the target.

  `dx` and `dy` are degrees, normally derived from a mouse drag.
  """
  @spec orbit(t(), number(), number()) :: t()
  def orbit(%__MODULE__{} = camera, dx, dy) do
    %{camera | yaw: wrap(camera.yaw + dx), pitch: clamp_pitch(camera.pitch + dy)}
  end

  @doc """
  Moves toward or away from the target.

  Multiplicative rather than additive, because a fixed step is too coarse when
  you are close and too slow when you are far. Clamped above zero: a distance
  of zero puts the eye on the target and the view matrix degenerates.
  """
  @spec dolly(t(), number()) :: t()
  def dolly(%__MODULE__{} = camera, factor) when factor > 0 do
    %{camera | distance: max(camera.distance * factor, 1.0e-3)}
  end

  @doc """
  Slides the target across the view plane.

  `dx` and `dy` are in the same units as the scene, scaled by the caller for
  the surface size. Panning moves the target, not the eye — the eye follows,
  because the camera is defined relative to what it is looking at.
  """
  @spec pan(t(), number(), number()) :: t()
  def pan(%__MODULE__{} = camera, dx, dy) do
    forward = Math.normalize(Math.sub(camera.target, eye(camera)))
    right = Math.normalize(Math.cross(forward, camera.up))
    up = Math.cross(right, forward)

    shift = Math.add(Math.scale(right, dx), Math.scale(up, dy))

    %{camera | target: Math.add(camera.target, shift)}
  end

  @doc """
  Frames a bounding box: centres the target on it and backs off far enough to
  see all of it.

  What "zoom to fit" and "home view" both call. The margin means the model does
  not touch the edges of the viewport, which reads as a mistake even when the
  framing is technically correct.
  """
  @spec fit(t(), Math.vec3(), Math.vec3(), number()) :: t()
  def fit(%__MODULE__{} = camera, {min_x, min_y, min_z}, {max_x, max_y, max_z}, margin \\ 1.4) do
    centre = {(min_x + max_x) / 2, (min_y + max_y) / 2, (min_z + max_z) / 2}
    extent = max(max(max_x - min_x, max_y - min_y), max_z - min_z)

    # Half the extent subtends half the field of view at this distance.
    half = max(extent, 1.0e-6) / 2.0
    distance = half / :math.tan(Math.rad(camera.fov) / 2.0) * margin

    %{camera | target: centre, distance: distance}
  end

  @doc "Where the camera is, derived from the target and the orbit."
  @spec eye(t()) :: Math.vec3()
  def eye(%__MODULE__{target: {tx, ty, tz}} = camera) do
    yaw = Math.rad(camera.yaw)
    pitch = Math.rad(camera.pitch)

    horizontal = camera.distance * :math.cos(pitch)

    {
      tx + horizontal * :math.sin(yaw),
      ty + camera.distance * :math.sin(pitch),
      tz + horizontal * :math.cos(yaw)
    }
  end

  @doc "The view matrix."
  @spec view(t()) :: Math.mat4()
  def view(%__MODULE__{} = camera) do
    Math.look_at(eye(camera), camera.target, camera.up)
  end

  @doc "The projection matrix for a surface of this aspect ratio."
  @spec projection(t(), number()) :: Math.mat4()
  def projection(%__MODULE__{} = camera, aspect) do
    Math.perspective(camera.fov, aspect, camera.near, camera.far)
  end

  @doc """
  Projection times view — everything that is a function of the camera and the
  surface, and nothing that is a function of an object.

  Computed once per frame and multiplied by each object's model matrix, rather
  than rebuilding the camera per object. That is the difference between one
  trigonometric evaluation per frame and one per link.
  """
  @spec view_projection(t(), number()) :: Math.mat4()
  def view_projection(%__MODULE__{} = camera, aspect) do
    Math.multiply(projection(camera, aspect), view(camera))
  end

  @doc """
  A standard view, as every CAD package offers.

  `:top`, `:bottom`, `:front`, `:back`, `:left`, `:right`, `:iso`. Distance and
  target are kept, so switching view keeps you looking at the same thing from a
  different side.
  """
  @spec look(t(), atom()) :: t()
  def look(%__MODULE__{} = camera, direction) do
    {yaw, pitch} = angles(direction)
    %{camera | yaw: yaw, pitch: clamp_pitch(pitch)}
  end

  defp angles(:top), do: {0.0, 89.0}
  defp angles(:bottom), do: {0.0, -89.0}
  defp angles(:front), do: {0.0, 0.0}
  defp angles(:back), do: {180.0, 0.0}
  defp angles(:right), do: {90.0, 0.0}
  defp angles(:left), do: {-90.0, 0.0}
  defp angles(:iso), do: {45.0, 30.0}

  defp angles(other) do
    raise ArgumentError,
          "unknown view #{inspect(other)}; known: " <>
            ":top, :bottom, :front, :back, :left, :right, :iso"
  end

  defp clamp_pitch(pitch) when pitch > @pitch_limit, do: @pitch_limit
  defp clamp_pitch(pitch) when pitch < -@pitch_limit, do: -@pitch_limit
  defp clamp_pitch(pitch), do: pitch * 1.0

  # Kept in 0..360 so a camera dragged in one direction forever does not
  # accumulate a yaw of forty thousand degrees, which is fine numerically right
  # up until it is not.
  defp wrap(degrees) do
    case :math.fmod(degrees, 360.0) do
      d when d < 0 -> d + 360.0
      d -> d
    end
  end
end
