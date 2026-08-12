# Golden-image test for the generated :image shader.
#
# Linking proves the GLSL is valid. This proves it is *correct*: it renders the
# shader offscreen with known inputs and checks the pixels that come back.
#
# Specifically it settles two things the transpile made uncertain:
#
#   1. Orientation. naga emits two Y negations which should cancel, so the
#      image must not be vertically flipped.
#   2. The ring-buffer scroll. Rust's `.fract()` came through as
#      `x - trunc(x)` rather than GLSL's floor-based `fract`, so the row
#      offset needs verifying rather than assuming.
#
#     mix run scripts/golden_image.exs

alias WxMVU.GLCanvas.Draw.Program
alias WxMVU.Renderer.GL

# Names are naga's, not ours - see the rename-pass note in the shader README.
defmodule ImageShader do
  use WxMVU.GLCanvas.Draw.Program,
    source: {:priv, :wx_mvu, "shaders/image"},
    blocks: [
      per_frame: [
        name: "type_6_block_0Fragment",
        binding: 0,
        fields: [row_offset: :f32, domain_min: :f32, domain_max: :f32]
      ]
    ],
    samplers: [{:"_group_0_binding_1_fs", 0}, {:"_group_0_binding_3_fs", 1}],
    vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
end

defmodule Golden do
  def section(t), do: IO.puts("\n\e[1m== #{t}\e[0m")
  def ok(m), do: IO.puts("  \e[32mok\e[0m    #{m}")

  def fail(m) do
    IO.puts("  \e[31mFAIL\e[0m  #{m}")
    Process.put(:failed, true)
  end

  # Allow a couple of LSB of slack for filtering/rounding.
  def close?({r1, g1, b1}, {r2, g2, b2}),
    do: abs(r1 - r2) <= 2 and abs(g1 - g2) <= 2 and abs(b1 - b2) <= 2

  def name({255, 0, 0}), do: "red"
  def name({0, 0, 255}), do: "blue"
  def name(rgb), do: inspect(rgb)
end

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

_wx = :wx.new()
frame = :wxFrame.new(:wx.null(), -1, ~c"golden", size: {120, 80})

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

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

{width, height} = {1, 2}

# Offscreen target.
target = GL.create_texture()
GL.bind_texture(:texture_2d, target)
GL.tex_image_2d(width, height, :rgba8, :rgba, :unsigned_byte, :binary.copy(<<0>>, width * height * 4))
GL.tex_parameter(:min_filter, :nearest)
GL.tex_parameter(:mag_filter, :nearest)

fbo = GL.create_framebuffer()
GL.bind_framebuffer(:both, fbo)
GL.framebuffer_texture_2d(:color, 0, target)

case GL.check_framebuffer_status() do
  :complete -> Golden.ok("framebuffer complete (#{width}x#{height} rgba8)")
  {:error, reason} -> Golden.fail("framebuffer incomplete: #{inspect(reason)}")
end

# Data grid: one column, two rows. Row 0 sits at the bottom in texture space.
data_texture = GL.create_texture()
GL.bind_texture(:texture_2d, data_texture)

GL.tex_image_2d(1, 2, :r32f, :red, :float, <<
  -100.0::float-32-native,
  0.0::float-32-native
>>)

GL.tex_parameter(:min_filter, :nearest)
GL.tex_parameter(:mag_filter, :nearest)
GL.tex_parameter(:wrap_s, :clamp_to_edge)
# Repeat, because the scroll wraps.
GL.tex_parameter(:wrap_t, :repeat)

# Colormap: 256x1 ramp from pure red at 0.0 to pure blue at 1.0.
colormap = for i <- 0..255, into: <<>>, do: <<255 - i::8, 0::8, i::8>>

colormap_texture = GL.create_texture()
GL.bind_texture(:texture_2d, colormap_texture)
GL.tex_image_2d(256, 1, :rgb8, :rgb, :unsigned_byte, colormap)
GL.tex_parameter(:min_filter, :nearest)
GL.tex_parameter(:mag_filter, :nearest)
GL.tex_parameter(:wrap_s, :clamp_to_edge)
GL.tex_parameter(:wrap_t, :clamp_to_edge)

# Fullscreen quad, matching the declared vertex layout.
vao = GL.create_vertex_array()
vbo = GL.create_buffer()
GL.bind_vertex_array(vao)
GL.bind_buffer(:array, vbo)

GL.buffer_data(
  :array,
  <<
    -1.0::float-32-native, -1.0::float-32-native, 0.0::float-32-native, 0.0::float-32-native,
    1.0::float-32-native, -1.0::float-32-native, 1.0::float-32-native, 0.0::float-32-native,
    -1.0::float-32-native, 1.0::float-32-native, 0.0::float-32-native, 1.0::float-32-native,
    1.0::float-32-native, 1.0::float-32-native, 1.0::float-32-native, 1.0::float-32-native
  >>,
  :static
)

# ---------------------------------------------------------------------------
# Program
# ---------------------------------------------------------------------------

program =
  case ImageShader.load() do
    {:ok, p} ->
      Golden.ok("Program.load/1 succeeded against generated GLSL")
      Golden.ok("computed block size #{ImageShader.block_size(:per_frame)} bytes")
      Golden.ok("stride #{ImageShader.stride()}, attribs #{length(ImageShader.vertex_layout())}")
      p

    {:error, log} ->
      Golden.fail("Program.load/1: #{log}")
      System.halt(1)
  end

Program.configure_vertex_attribs(program)

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------

render = fn row_offset ->
  GL.bind_framebuffer(:both, fbo)
  GL.viewport(0, 0, width, height)
  GL.clear_color(0.0, 0.0, 0.0, 1.0)
  GL.clear(:color)

  Program.bind(program)

  Program.set_block(program, :per_frame, %{
    row_offset: row_offset,
    domain_min: -100.0,
    domain_max: 0.0
  })

  GL.active_texture(0)
  GL.bind_texture(:texture_2d, data_texture)
  GL.active_texture(1)
  GL.bind_texture(:texture_2d, colormap_texture)

  GL.bind_vertex_array(vao)
  GL.draw_arrays(:triangle_strip, 0, 4)

  GL.assert_no_error!()

  # readPixels returns bottom-up: first row of the binary is the bottom row.
  <<br, bg, bb, _ba, tr, tg, tb, _ta>> =
    GL.read_pixels(0, 0, width, height, :rgba, :unsigned_byte)

  {{br, bg, bb}, {tr, tg, tb}}
end

Golden.section("Orientation (row_offset = 0.0)")

{bottom, top} = render.(0.0)
IO.puts("  bottom=#{Golden.name(bottom)}  top=#{Golden.name(top)}")

# Data row 0 = -100.0 -> domain 0.0 -> colormap red, and row 0 is the bottom of
# the texture. If naga's two Y negations did not cancel, this would be flipped.
if Golden.close?(bottom, {255, 0, 0}) and Golden.close?(top, {0, 0, 255}) do
  Golden.ok("not flipped - the two Y negations cancel")
else
  Golden.fail("expected bottom red / top blue, got bottom=#{inspect(bottom)} top=#{inspect(top)}")
end

Golden.section("Scroll (row_offset = 0.5)")

{bottom2, top2} = render.(0.5)
IO.puts("  bottom=#{Golden.name(bottom2)}  top=#{Golden.name(top2)}")

if Golden.close?(bottom2, {0, 0, 255}) and Golden.close?(top2, {255, 0, 0}) do
  Golden.ok("rows swapped - trunc-based fract wraps correctly here")
else
  Golden.fail("expected rows to swap, got bottom=#{inspect(bottom2)} top=#{inspect(top2)}")
end

Golden.section("Domain clamp (row_offset = 0.0, domain -50..0)")

# -100.0 is below domain_min, so it must clamp to 0.0 -> red, not wrap or NaN.
GL.bind_framebuffer(:both, fbo)
Program.bind(program)

Program.set_block(program, :per_frame, %{
  row_offset: 0.0,
  domain_min: -50.0,
  domain_max: 0.0
})

GL.bind_vertex_array(vao)
GL.draw_arrays(:triangle_strip, 0, 4)
<<cr, cg, cb, _, _, _, _, _>> = GL.read_pixels(0, 0, width, height, :rgba, :unsigned_byte)

if Golden.close?({cr, cg, cb}, {255, 0, 0}) do
  Golden.ok("out-of-domain value clamps to the low end")
else
  Golden.fail("expected clamp to red, got #{inspect({cr, cg, cb})}")
end

# ---------------------------------------------------------------------------

GL.bind_default_framebuffer()
Program.delete(program)
GL.delete_framebuffer(fbo)
GL.delete_texture(target)
GL.delete_texture(data_texture)
GL.delete_texture(colormap_texture)
GL.delete_vertex_array(vao)
GL.delete_buffer(vbo)
:wxGLContext.destroy(context)
:wxFrame.destroy(frame)

if Process.get(:failed) do
  IO.puts("\n\e[31mFAILED\e[0m\n")
  System.halt(1)
else
  IO.puts("\n\e[32mGenerated shader renders correctly\e[0m\n")
end
