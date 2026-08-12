# Golden-image test for the generated :line shader.
#
# :line has been linking since it was written, which proves nothing about its
# geometry. The vertex stage expands a polyline into quads using a screen-space
# perpendicular and an aspect correction, and every part of that can be wrong
# in a way that still links.
#
# The assertion is deliberately a pixel count: draw a horizontal line of a known
# width and count how many rows of the framebuffer it actually covers. That
# checks the expansion happened at all, that it went perpendicular to the
# segment rather than along it, and that the width landed in pixels rather than
# in NDC.
#
# It also checks something subtler. LineUniforms is referenced from *both*
# stages, and naga names a uniform block per stage. If the rewriter renames only
# one of them, GLSL sees two differently-named blocks, the vertex stage silently
# receives no uniform data, and line_width reads as zero - producing an empty
# framebuffer rather than an error. Varying the width and asserting the row
# count follows is what catches that.
#
#     mix run scripts/golden_line.exs

alias WxMVU.GLCanvas.Draw.Program
alias WxMVU.Renderer.GL

defmodule LineShader do
  use WxMVU.GLCanvas.Draw.Program,
    source: {:priv, :wx_mvu, "shaders/line"},
    blocks: [
      per_frame: [
        name: "LineUniforms",
        binding: 0,
        fields: [color: :vec4, viewport: :vec2, line_width: :f32]
      ]
    ],
    samplers: [],
    vertex_layout: [
      a_position: {:f32, 2},
      a_neighbor: {:f32, 2},
      a_side: {:f32, 1}
    ]
end

defmodule Golden do
  def section(t), do: IO.puts("\n\e[1m== #{t}\e[0m")
  def ok(m), do: IO.puts("  \e[32mok\e[0m    #{m}")

  def fail(m) do
    IO.puts("  \e[31mFAIL\e[0m  #{m}")
    Process.put(:failed, true)
  end
end

# ---------------------------------------------------------------------------

_wx = :wx.new()
frame = :wxFrame.new(:wx.null(), -1, ~c"golden line", size: {120, 80})

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

# A single horizontal segment across the middle, as a triangle strip.
#
# a_neighbor must yield the same direction at both ends, otherwise the
# perpendicular flips at the far end and the quad becomes a bowtie. So the end
# vertices carry a neighbour extrapolated along the segment rather than the
# start point.
vao = GL.create_vertex_array()
vbo = GL.create_buffer()
GL.bind_vertex_array(vao)
GL.bind_buffer(:array, vbo)

f = fn v -> <<v::float-32-native>> end

vertices =
  IO.iodata_to_binary([
    # position        neighbour        side
    f.(-0.8), f.(0.0), f.(0.8), f.(0.0), f.(1.0),
    f.(-0.8), f.(0.0), f.(0.8), f.(0.0), f.(-1.0),
    f.(0.8), f.(0.0), f.(2.4), f.(0.0), f.(1.0),
    f.(0.8), f.(0.0), f.(2.4), f.(0.0), f.(-1.0)
  ])

GL.buffer_data(:array, vertices, :static)

program =
  case LineShader.load() do
    {:ok, p} ->
      Golden.ok("Program.load/1 succeeded (no samplers, 3 attributes)")
      Golden.ok("block size #{LineShader.block_size(:per_frame)} bytes, stride #{LineShader.stride()}")
      p

    {:error, log} ->
      Golden.fail("Program.load/1: #{log}")
      System.halt(1)
  end

Program.configure_vertex_attribs(program)

# ---------------------------------------------------------------------------

red = {255, 0, 0}

render_and_count = fn line_width ->
  GL.bind_framebuffer(:both, fbo)
  GL.viewport(0, 0, size, size)
  GL.clear_color(0.0, 0.0, 0.0, 1.0)
  GL.clear(:color)

  Program.bind(program)

  Program.set_block(program, :per_frame, %{
    color: {1.0, 0.0, 0.0, 1.0},
    viewport: {size * 1.0, size * 1.0},
    line_width: line_width
  })

  GL.bind_vertex_array(vao)
  GL.draw_arrays(:triangle_strip, 0, 4)
  GL.assert_no_error!()

  pixels = GL.read_pixels(0, 0, size, size, :rgba, :unsigned_byte)

  # Sample the centre column of every row.
  for row <- 0..(size - 1) do
    offset = (row * size + div(size, 2)) * 4
    <<_::binary-size(offset), r, g, b, _a, _::binary>> = pixels
    {r, g, b}
  end
  |> Enum.count(&(&1 == red))
end

Golden.section("Expansion width")

for {width, expected} <- [{4.0, 4}, {8.0, 8}, {2.0, 2}] do
  covered = render_and_count.(width)

  if covered == expected do
    Golden.ok("line_width #{width} covers #{covered} rows")
  else
    Golden.fail("line_width #{width} should cover #{expected} rows, covered #{covered}")
  end
end

Golden.section("Uniforms reach the vertex stage")

# If only the fragment stage's block were renamed, the vertex stage would get no
# uniform data, line_width would read as 0, and every width would collapse to
# the same coverage. Distinct counts prove the block links across both stages.
thin = render_and_count.(2.0)
thick = render_and_count.(8.0)

if thick > thin and thin > 0 do
  Golden.ok("width changes coverage (#{thin} -> #{thick} rows), so both stages share the block")
else
  Golden.fail("coverage did not track line_width: #{thin} and #{thick} rows")
end

# ---------------------------------------------------------------------------

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
  IO.puts("\n\e[32m:line renders correctly\e[0m\n")
end
