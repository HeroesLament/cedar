# Golden-image test for the generated :mesh shader.
#
# Everything here is chosen to fail loudly if a matrix is transposed or a mat3
# is packed at the wrong stride — both of which produce output that looks
# entirely plausible.
#
#   * The model matrix is a *translation*. An identity is symmetric, so it
#     passes whether you write column-major or row-major; a translation puts
#     its offset in elements 12..14 column-major and 3/7/11 row-major, so
#     getting it wrong moves the geometry somewhere else entirely.
#
#   * The normal matrix rotates the surface normal 90 degrees. If Std140 packed
#     mat3 as three tight vec3 rather than three vec4-padded columns, the
#     shader would read the columns misaligned and the lighting would be wrong
#     rather than absent.
#
#   * Light direction is swept, which exercises the vec3 field sitting at
#     offset 112 with four bytes of padding after it.
#
# This is the first exercise of Std140.pack/2 for mat4 and mat3 at all.
#
#     mix run scripts/golden_mesh.exs

alias WxMVU.GLCanvas.Draw.Program
alias WxMVU.Renderer.GL

defmodule MeshShader do
  use WxMVU.GLCanvas.Draw.Program,
    source: {:priv, :wx_mvu, "shaders/mesh"},
    blocks: [
      per_frame: [
        name: "MeshUniforms",
        binding: 0,
        fields: [
          mvp: :mat4,
          normal_matrix: :mat3,
          light_direction: :vec3,
          base_color: :vec4
        ]
      ]
    ],
    samplers: [],
    vertex_layout: [a_position: {:f32, 3}, a_normal: {:f32, 3}]
end

defmodule Golden do
  def section(t), do: IO.puts("\n\e[1m== #{t}\e[0m")
  def ok(m), do: IO.puts("  \e[32mok\e[0m    #{m}")

  def fail(m) do
    IO.puts("  \e[31mFAIL\e[0m  #{m}")
    Process.put(:failed, true)
  end

  def close?(a, b, tolerance \\ 6), do: abs(a - b) <= tolerance
end

_wx = :wx.new()
frame = :wxFrame.new(:wx.null(), -1, ~c"golden mesh", size: {120, 80})

attribs = [
  1,
  4,
  11,
  24,
  12,
  8,
  :wxe_util.get_const(:wx_GL_CORE_PROFILE),
  :wxe_util.get_const(:wx_GL_MAJOR_VERSION),
  4,
  :wxe_util.get_const(:wx_GL_MINOR_VERSION),
  1,
  0
]

canvas = :wxGLCanvas.new(frame, attribList: attribs)
context = :wxGLContext.new(canvas)
:wxFrame.show(frame)
:wxGLCanvas.setCurrent(canvas, context)

Golden.section("Setup")
IO.puts("  #{:gl.getString(WxEx.Constants.OpenGL.gl_VERSION()) |> to_string()}")

size = 16

target = GL.create_texture()
GL.bind_texture(:texture_2d, target)
GL.tex_image_2d(size, size, :rgba8, :rgba, :unsigned_byte, :binary.copy(<<0>>, size * size * 4))
GL.tex_parameter(:min_filter, :nearest)
GL.tex_parameter(:mag_filter, :nearest)

fbo = GL.create_framebuffer()
GL.bind_framebuffer(:both, fbo)
GL.framebuffer_texture_2d(:color, 0, target)

case GL.check_framebuffer_status() do
  :complete -> Golden.ok("framebuffer complete (#{size}x#{size} rgba8)")
  {:error, reason} -> Golden.fail("framebuffer incomplete: #{inspect(reason)}")
end

# A quad covering the LEFT half of clip space, with every normal pointing
# along +X. The normal matrix is what turns that into something the light can
# see, so a broken mat3 shows up as darkness rather than as geometry moving.
f = fn v -> <<v * 1.0::float-32-native>> end

vertices =
  IO.iodata_to_binary([
    # position           normal
    f.(-1.0), f.(-1.0), f.(0.0), f.(1.0), f.(0.0), f.(0.0),
    f.(0.0), f.(-1.0), f.(0.0), f.(1.0), f.(0.0), f.(0.0),
    f.(-1.0), f.(1.0), f.(0.0), f.(1.0), f.(0.0), f.(0.0),
    f.(0.0), f.(1.0), f.(0.0), f.(1.0), f.(0.0), f.(0.0)
  ])

vao = GL.create_vertex_array()
vbo = GL.create_buffer()
GL.bind_vertex_array(vao)
GL.bind_buffer(:array, vbo)
GL.buffer_data(:array, vertices, :static)

program =
  case MeshShader.load() do
    {:ok, p} ->
      Golden.ok("Program.load/1 succeeded, block #{MeshShader.block_size(:per_frame)} bytes")
      Golden.ok("stride #{MeshShader.stride()}, #{length(MeshShader.vertex_layout())} attributes")
      p

    {:error, log} ->
      Golden.fail("Program.load/1: #{log}")
      System.halt(1)
  end

Program.configure_vertex_attribs(program)

# Column-major, as GLSL expects.
identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
translate_x = fn tx -> [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, tx, 0, 0, 1] end

# Rotation about Y by -90 degrees: maps the +X normal onto +Z, towards the
# camera and towards the light. Columns, not rows.
rotate_x_to_z = [0, 0, 1, 0, 1, 0, -1, 0, 0]

render = fn mvp, normal_matrix, light ->
  GL.bind_framebuffer(:both, fbo)
  GL.viewport(0, 0, size, size)
  GL.clear_color(0.0, 0.0, 0.0, 1.0)
  GL.clear(:color)

  Program.bind(program)

  Program.set_block(program, :per_frame, %{
    mvp: mvp,
    normal_matrix: normal_matrix,
    light_direction: light,
    base_color: {1.0, 1.0, 1.0, 1.0}
  })

  GL.bind_vertex_array(vao)
  GL.draw_arrays(:triangle_strip, 0, 4)
  GL.assert_no_error!()

  pixels = GL.read_pixels(0, 0, size, size, :rgba, :unsigned_byte)

  sample = fn col, row ->
    offset = (row * size + col) * 4
    <<_::binary-size(offset), r, _g, _b, _a, _::binary>> = pixels
    r
  end

  {sample.(4, 8), sample.(12, 8)}
end

# ---------------------------------------------------------------------------

Golden.section("Normal matrix (mat3 packing)")

{left, right} = render.(identity, rotate_x_to_z, {0.0, 0.0, 1.0})
IO.puts("  left=#{left} right=#{right}")

cond do
  left == 0 ->
    Golden.fail("nothing drawn on the left half - geometry or mvp is wrong")

  Golden.close?(left, 255) ->
    Golden.ok("normal rotated onto the light: full intensity (#{left})")

  true ->
    Golden.fail(
      "expected ~255 with the normal rotated onto the light, got #{left}. " <>
        "A mat3 packed as three tight vec3 instead of vec4-padded columns " <>
        "would land here."
    )
end

if right == 0 do
  Golden.ok("right half empty, as the quad only covers the left")
else
  Golden.fail("right half should be empty, got #{right}")
end

Golden.section("Model matrix (column-major, not transposed)")

# Translating by +1 in x moves the quad from the left half to the right half.
# Row-major packing puts the offset somewhere else entirely and the quad does
# not move - which is exactly the failure an identity matrix cannot detect.
{left2, right2} = render.(translate_x.(1.0), rotate_x_to_z, {0.0, 0.0, 1.0})
IO.puts("  left=#{left2} right=#{right2}")

cond do
  right2 > 0 and left2 == 0 ->
    Golden.ok("quad translated to the right half")

  left2 > 0 and right2 == 0 ->
    Golden.fail("quad did not move - mat4 is likely packed row-major")

  true ->
    Golden.fail("unexpected coverage after translation: left=#{left2} right=#{right2}")
end

Golden.section("Lighting responds to direction")

# The vec3 light_direction sits at offset 112 with padding after it, so a
# packing error here shows up as intensity not tracking the light.
lit = render.(identity, rotate_x_to_z, {0.0, 0.0, 1.0}) |> elem(0)
away = render.(identity, rotate_x_to_z, {0.0, 0.0, -1.0}) |> elem(0)
edge = render.(identity, rotate_x_to_z, {0.0, 1.0, 0.0}) |> elem(0)

IO.puts("  towards=#{lit}  away=#{away}  perpendicular=#{edge}")

# AMBIENT is 0.15 in the shader, so a surface facing away should sit near 38.
ambient_expected = round(0.15 * 255)

cond do
  not Golden.close?(away, ambient_expected) ->
    Golden.fail("facing away should be the ambient floor ~#{ambient_expected}, got #{away}")

  not Golden.close?(edge, ambient_expected) ->
    Golden.fail("perpendicular should also be ~#{ambient_expected}, got #{edge}")

  lit <= away ->
    Golden.fail("facing the light (#{lit}) is not brighter than facing away (#{away})")

  true ->
    Golden.ok("intensity tracks the light: #{away} facing away, #{lit} facing towards")
end

GL.bind_default_framebuffer()
Program.delete(program)
GL.delete_framebuffer(fbo)
GL.delete_texture(target)
GL.delete_vertex_array(vao)
GL.delete_buffer(vbo)
:wxGLContext.destroy(context)
:wxFrame.destroy(frame)

if Process.get(:failed) do
  IO.puts("\n\e[31mFAILED\e[0m\n")
  System.halt(1)
else
  IO.puts("\n\e[32m:mesh renders correctly, mat4 and mat3 pack correctly\e[0m\n")
end
