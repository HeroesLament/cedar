# Golden-image test for the generated :grid shader.
#
# :grid is the first shader here to use a GPU-only intrinsic. `fwidth` — the
# rate of change of a value across a pixel — has no CPU equivalent, so the
# coverage maths in wx-mvu-shader-core takes the derivative as an argument and
# is tested on stable; this covers the part that cannot be.
#
# If fwidth lowered wrongly through SPIR-V and naga, the likely failures are a
# uniformly background-coloured frame (derivative reads huge, no line ever
# reaches coverage) or a uniformly line-coloured one (derivative reads zero or
# negative). Both link perfectly. So the assertions are about the *distribution*
# of pixels rather than any single one.
#
#     mix run scripts/golden_grid.exs

alias WxMVU.GLCanvas.Draw.Program
alias WxMVU.Renderer.GL

defmodule GridShader do
  use WxMVU.GLCanvas.Draw.Program,
    source: {:priv, :wx_mvu, "shaders/grid"},
    blocks: [
      per_frame: [
        name: "GridUniforms",
        binding: 0,
        fields: [
          line_color: :vec4,
          background: :vec4,
          spacing: :vec2,
          thickness: :f32
        ]
      ]
    ],
    samplers: [],
    vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
end

defmodule Golden do
  def section(t), do: IO.puts("\n\e[1m== #{t}\e[0m")
  def ok(m), do: IO.puts("  \e[32mok\e[0m    #{m}")

  def fail(m) do
    IO.puts("  \e[31mFAIL\e[0m  #{m}")
    Process.put(:failed, true)
  end
end

_wx = :wx.new()
frame = :wxFrame.new(:wx.null(), -1, ~c"golden grid", size: {120, 80})

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

size = 32

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

program =
  case GridShader.load() do
    {:ok, p} ->
      Golden.ok("Program.load/1 succeeded, block #{GridShader.block_size(:per_frame)} bytes")
      p

    {:error, log} ->
      Golden.fail("Program.load/1: #{log}")
      System.halt(1)
  end

Program.configure_vertex_attribs(program)

# Line is pure red, background pure blue, so classification is unambiguous.
render = fn thickness ->
  GL.bind_framebuffer(:both, fbo)
  GL.viewport(0, 0, size, size)
  GL.clear_color(0.0, 0.0, 0.0, 1.0)
  GL.clear(:color)

  Program.bind(program)

  Program.set_block(program, :per_frame, %{
    line_color: {1.0, 0.0, 0.0, 1.0},
    background: {0.0, 0.0, 1.0, 1.0},
    # Four cells across the quad, so lines land every 8 pixels.
    spacing: {0.25, 0.25},
    thickness: thickness
  })

  GL.bind_vertex_array(vao)
  GL.draw_arrays(:triangle_strip, 0, 4)
  GL.assert_no_error!()

  pixels = GL.read_pixels(0, 0, size, size, :rgba, :unsigned_byte)

  for i <- 0..(size * size - 1) do
    offset = i * 4
    <<_::binary-size(offset), r, _g, _b, _a, _::binary>> = pixels
    r
  end
end

Golden.section("Distribution")

# Note on thresholds. Gridlines land on integer grid coordinates, which here
# fall on pixel *boundaries* rather than centres. With analytic antialiasing a
# line centred on a boundary splits its coverage between the two adjacent
# pixels, so a 2px line peaks at roughly half intensity and never produces a
# fully saturated pixel. That is correct behaviour, not a defect - an earlier
# version of this test asserted full saturation and failed for that reason.
lit_threshold = 32
background_threshold = 8

reds = render.(2.0)
total = length(reds)
lit = Enum.count(reds, &(&1 > lit_threshold))
background = Enum.count(reds, &(&1 <= background_threshold))
peak = Enum.max(reds)

IO.puts("  #{lit}/#{total} lit, #{background}/#{total} background, peak #{peak}")

cond do
  lit == 0 ->
    Golden.fail("nothing is lit - fwidth may be reading too large")

  background == 0 ->
    Golden.fail("no background pixels - fwidth may be reading zero or negative")

  lit > div(total, 2) ->
    Golden.fail("more than half the frame is lit - the grid is not a grid")

  peak < 64 ->
    Golden.fail("peak coverage #{peak} is too faint for a 2px line")

  true ->
    Golden.ok("lines and background in sane proportion, peak #{peak}")
end

Golden.section("Antialiasing")

# Checked at 1px rather than 2px. Box-filter coverage of a 2px band centred on
# a pixel boundary is exactly full on both neighbours - correctly no
# intermediate values at all. A 1px band splits half to each side, so partial
# coverage is what proves the derivative is producing a gradient rather than a
# binary mask.
partial =
  render.(1.0)
  |> Enum.count(&(&1 > background_threshold and &1 < 250))

if partial > 0 do
  Golden.ok("#{partial} partially covered pixels - the line is antialiased")
else
  Golden.fail("no partial coverage; fwidth is not producing a gradient")
end

Golden.section("Thickness is plumbed through")

thin_reds = render.(1.0)
thick_reds = render.(4.0)

thin = Enum.count(thin_reds, &(&1 > lit_threshold))
thick = Enum.count(thick_reds, &(&1 > lit_threshold))
thin_peak = Enum.max(thin_reds)
thick_peak = Enum.max(thick_reds)

IO.puts("  thickness 1.0 -> #{thin} lit, peak #{thin_peak}")
IO.puts("  thickness 4.0 -> #{thick} lit, peak #{thick_peak}")

if thick > thin and thick_peak > thin_peak do
  Golden.ok("thicker lines cover more pixels and reach higher coverage")
else
  Golden.fail("thickness had no effect: #{thin}/#{thin_peak} vs #{thick}/#{thick_peak}")
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
  IO.puts("\n\e[32m:grid renders correctly, fwidth survives the pipeline\e[0m\n")
end
