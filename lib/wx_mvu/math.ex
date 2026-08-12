defmodule WxMVU.Math do
  @moduledoc """
  The small amount of linear algebra a viewport needs.

  Matrices are flat 16-element lists in **column-major** order, which is what
  OpenGL and std140 both want, so a matrix built here goes into a uniform block
  with no transposition step and no chance of a silent transpose bug.

      model = Math.translation({0.0, 0.0, -4.0})
      view = Math.look_at({3.0, 3.0, 3.0}, {0.0, 0.0, 0.0}, {0.0, 1.0, 0.0})
      projection = Math.perspective(45.0, 16 / 9, 0.1, 100.0)

      mvp = Math.multiply(projection, Math.multiply(view, model))

  Vectors are 3-tuples. There is deliberately no vector *type* — a `{x, y, z}`
  tuple is already the idiomatic Elixir spelling and needs no wrapper.

  ## Conventions

  Right-handed, looking down -Z, with clip depth in `-1.0..1.0`. This is the
  OpenGL convention rather than Vulkan's or Direct3D's, and it is the one the
  generated GLSL is compiled against.

  Angles are in **degrees** everywhere in the public API. Radians are correct
  and degrees are what people type; `deg/1` and `rad/1` convert if you need to
  cross the boundary yourself.
  """

  @type vec3 :: {number(), number(), number()}
  @type mat4 :: [float()]
  @type mat3 :: [float()]

  # ==========================================================================
  # Angles
  # ==========================================================================

  @doc "Degrees to radians."
  @spec rad(number()) :: float()
  def rad(degrees), do: degrees * :math.pi() / 180.0

  @doc "Radians to degrees."
  @spec deg(number()) :: float()
  def deg(radians), do: radians * 180.0 / :math.pi()

  # ==========================================================================
  # Vectors
  # ==========================================================================

  @doc "Component-wise subtraction."
  @spec sub(vec3(), vec3()) :: vec3()
  def sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}

  @doc "Component-wise addition."
  @spec add(vec3(), vec3()) :: vec3()
  def add({ax, ay, az}, {bx, by, bz}), do: {ax + bx, ay + by, az + bz}

  @doc "Scalar multiple."
  @spec scale(vec3(), number()) :: vec3()
  def scale({x, y, z}, s), do: {x * s, y * s, z * s}

  @doc "Dot product."
  @spec dot(vec3(), vec3()) :: float()
  def dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  @doc "Cross product, right-handed."
  @spec cross(vec3(), vec3()) :: vec3()
  def cross({ax, ay, az}, {bx, by, bz}) do
    {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
  end

  @doc "Euclidean length."
  @spec length(vec3()) :: float()
  def length(v), do: :math.sqrt(dot(v, v))

  @doc """
  Unit vector, or `{0.0, 0.0, 0.0}` for a zero-length input.

  Returning zero rather than raising matches what the shaders do: degenerate
  geometry is common in real data and a NaN propagating into a vertex position
  takes the whole primitive with it.
  """
  @spec normalize(vec3()) :: vec3()
  def normalize({x, y, z} = v) do
    case __MODULE__.length(v) do
      0.0 -> {0.0, 0.0, 0.0}
      len -> {x / len, y / len, z / len}
    end
  end

  # ==========================================================================
  # Matrices
  # ==========================================================================

  @identity [
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0
  ]

  @doc "The 4x4 identity."
  @spec identity() :: mat4()
  def identity, do: @identity

  @doc """
  Matrix product, `a * b` — `b` is applied first.

  So a model-view-projection is `multiply(projection, multiply(view, model))`,
  reading right to left exactly as the maths does.
  """
  @spec multiply(mat4(), mat4()) :: mat4()
  def multiply(a, b) when is_list(a) and is_list(b) do
    at = List.to_tuple(a)
    bt = List.to_tuple(b)

    for col <- 0..3, row <- 0..3 do
      elem(at, row) * elem(bt, col * 4) +
        elem(at, 4 + row) * elem(bt, col * 4 + 1) +
        elem(at, 8 + row) * elem(bt, col * 4 + 2) +
        elem(at, 12 + row) * elem(bt, col * 4 + 3)
    end
  end

  @doc "Product of several matrices, left to right — the leftmost applies last."
  @spec multiply([mat4()]) :: mat4()
  def multiply([first | rest]), do: Enum.reduce(rest, first, &multiply(&2, &1))

  @doc "Transpose."
  @spec transpose(mat4()) :: mat4()
  def transpose(m) do
    t = List.to_tuple(m)
    for row <- 0..3, col <- 0..3, do: elem(t, col * 4 + row)
  end

  @doc "Translation."
  @spec translation(vec3()) :: mat4()
  def translation({x, y, z}) do
    [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, x * 1.0, y * 1.0, z * 1.0, 1.0]
  end

  @doc "Non-uniform scale. A number scales all three axes."
  @spec scaling(vec3() | number()) :: mat4()
  def scaling(s) when is_number(s), do: scaling({s, s, s})

  def scaling({x, y, z}) do
    [x * 1.0, 0.0, 0.0, 0.0, 0.0, y * 1.0, 0.0, 0.0, 0.0, 0.0, z * 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
  end

  @doc """
  Rotation of `degrees` about an arbitrary axis.

  The axis is normalized for you; a zero axis yields the identity rather than
  a matrix full of NaN.
  """
  @spec rotation(vec3(), number()) :: mat4()
  def rotation(axis, degrees) do
    case normalize(axis) do
      {0.0, 0.0, 0.0} ->
        identity()

      {x, y, z} ->
        a = rad(degrees)
        c = :math.cos(a)
        s = :math.sin(a)
        t = 1.0 - c

        [
          t * x * x + c,
          t * x * y + s * z,
          t * x * z - s * y,
          0.0,
          t * x * y - s * z,
          t * y * y + c,
          t * y * z + s * x,
          0.0,
          t * x * z + s * y,
          t * y * z - s * x,
          t * z * z + c,
          0.0,
          0.0,
          0.0,
          0.0,
          1.0
        ]
    end
  end

  @doc "Rotation about X, in degrees."
  @spec rotation_x(number()) :: mat4()
  def rotation_x(degrees), do: rotation({1.0, 0.0, 0.0}, degrees)

  @doc "Rotation about Y, in degrees."
  @spec rotation_y(number()) :: mat4()
  def rotation_y(degrees), do: rotation({0.0, 1.0, 0.0}, degrees)

  @doc "Rotation about Z, in degrees."
  @spec rotation_z(number()) :: mat4()
  def rotation_z(degrees), do: rotation({0.0, 0.0, 1.0}, degrees)

  @doc """
  Perspective projection.

  `fovy` is the vertical field of view in degrees. Depth maps to `-1.0..1.0`,
  the OpenGL convention.
  """
  @spec perspective(number(), number(), number(), number()) :: mat4()
  def perspective(fovy, aspect, near, far)
      when aspect > 0 and near > 0 and far > near do
    f = 1.0 / :math.tan(rad(fovy) / 2.0)

    [
      f / aspect,
      0.0,
      0.0,
      0.0,
      0.0,
      f,
      0.0,
      0.0,
      0.0,
      0.0,
      (far + near) / (near - far),
      -1.0,
      0.0,
      0.0,
      2.0 * far * near / (near - far),
      0.0
    ]
  end

  def perspective(_fovy, aspect, near, far) do
    raise ArgumentError,
          "perspective requires aspect > 0, near > 0 and far > near, got " <>
            "aspect=#{inspect(aspect)} near=#{inspect(near)} far=#{inspect(far)}"
  end

  @doc "Orthographic projection."
  @spec orthographic(number(), number(), number(), number(), number(), number()) :: mat4()
  def orthographic(left, right, bottom, top, near, far) do
    [
      2.0 / (right - left),
      0.0,
      0.0,
      0.0,
      0.0,
      2.0 / (top - bottom),
      0.0,
      0.0,
      0.0,
      0.0,
      -2.0 / (far - near),
      0.0,
      -(right + left) / (right - left),
      -(top + bottom) / (top - bottom),
      -(far + near) / (far - near),
      1.0
    ]
  end

  @doc """
  A view matrix placing the camera at `eye` looking at `target`.

  `up` only has to be *roughly* up — it is used to establish handedness and is
  re-orthogonalised, so a camera tumbling past vertical does not need its up
  vector maintained by hand. It must not be parallel to the view direction,
  which is the one degenerate case, and yields the identity rather than NaN.
  """
  @spec look_at(vec3(), vec3(), vec3()) :: mat4()
  def look_at(eye, target, up \\ {0.0, 1.0, 0.0}) do
    forward = normalize(sub(target, eye))
    side = normalize(cross(forward, up))

    if side == {0.0, 0.0, 0.0} or forward == {0.0, 0.0, 0.0} do
      identity()
    else
      {ux, uy, uz} = cross(side, forward)
      {sx, sy, sz} = side
      {fx, fy, fz} = forward

      [
        sx,
        ux,
        -fx,
        0.0,
        sy,
        uy,
        -fy,
        0.0,
        sz,
        uz,
        -fz,
        0.0,
        -dot(side, eye),
        -dot({ux, uy, uz}, eye),
        dot(forward, eye),
        1.0
      ]
    end
  end

  @doc """
  The 3x3 normal matrix for a model matrix: the inverse transpose of its
  upper-left 3x3.

  Needed because a normal transformed by a non-uniformly scaled model matrix
  stops being perpendicular to its surface — squash a sphere and the naive
  normals tilt the wrong way, lighting the wrong side of the bulge.

  Returns nine floats, column-major, ready for a `:mat3` uniform field. A
  singular matrix — a scale to zero on some axis — returns the identity rather
  than infinities.
  """
  @spec normal_matrix(mat4()) :: mat3()
  def normal_matrix(m) do
    t = List.to_tuple(m)
    a = for i <- [0, 1, 2, 4, 5, 6, 8, 9, 10], do: elem(t, i)
    [m00, m01, m02, m10, m11, m12, m20, m21, m22] = a

    det =
      m00 * (m11 * m22 - m12 * m21) -
        m10 * (m01 * m22 - m02 * m21) +
        m20 * (m01 * m12 - m02 * m11)

    if abs(det) < 1.0e-12 do
      [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
    else
      inv = 1.0 / det

      # Inverse, column-major.
      i00 = (m11 * m22 - m12 * m21) * inv
      i01 = (m02 * m21 - m01 * m22) * inv
      i02 = (m01 * m12 - m02 * m11) * inv
      i10 = (m12 * m20 - m10 * m22) * inv
      i11 = (m00 * m22 - m02 * m20) * inv
      i12 = (m02 * m10 - m00 * m12) * inv
      i20 = (m10 * m21 - m11 * m20) * inv
      i21 = (m01 * m20 - m00 * m21) * inv
      i22 = (m00 * m11 - m01 * m10) * inv

      # ...then transposed, which for column-major storage is a relabel.
      [i00, i10, i20, i01, i11, i21, i02, i12, i22]
    end
  end

  @doc """
  Transforms a point by a matrix, dividing through by w.

  For checking a projection by hand, and for hit-testing later.
  """
  @spec transform_point(mat4(), vec3()) :: vec3()
  def transform_point(m, {x, y, z}) do
    t = List.to_tuple(m)

    tx = elem(t, 0) * x + elem(t, 4) * y + elem(t, 8) * z + elem(t, 12)
    ty = elem(t, 1) * x + elem(t, 5) * y + elem(t, 9) * z + elem(t, 13)
    tz = elem(t, 2) * x + elem(t, 6) * y + elem(t, 10) * z + elem(t, 14)
    tw = elem(t, 3) * x + elem(t, 7) * y + elem(t, 11) * z + elem(t, 15)

    case tw do
      0.0 -> {tx, ty, tz}
      w -> {tx / w, ty / w, tz / w}
    end
  end
end
