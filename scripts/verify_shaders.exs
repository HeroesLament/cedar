# Verifies committed GLSL against a real OpenGL 4.1 core context.
#
# Generating GLSL is not the acceptance criterion - linking on the driver is,
# and on macOS that driver is Apple's frozen 4.1 implementation, the strictest
# of the three major ones. Run this before committing regenerated artifacts.
#
#     mix run scripts/verify_shaders.exs
#
# Exits non-zero if anything fails to compile or link.

alias WxMVU.GLCanvas.Draw.Std140
alias WxMVU.Renderer.GL
alias WxEx.Constants.OpenGL

defmodule Verify do
  def section(title), do: IO.puts("\n\e[1m== #{title}\e[0m")
  def ok(msg), do: IO.puts("  \e[32mok\e[0m    #{msg}")
  def info(msg), do: IO.puts("        #{msg}")

  def fail(msg) do
    IO.puts("  \e[31mFAIL\e[0m  #{msg}")
    Process.put(:failed, true)
  end

  def safe(fun, default \\ :unavailable) do
    fun.()
  rescue
    e -> {:error, Exception.message(e)}
  catch
    _, _ -> default
  end
end

# ============================================================================
# Context
# ============================================================================

Verify.section("Context")

_wx = :wx.new()
frame = :wxFrame.new(:wx.null(), -1, ~c"wx_mvu shader verify", size: {200, 100})

# Request an explicit 4.1 core profile. Without this, macOS hands back a
# legacy 2.1 context and every `#version 410 core` shader fails to compile.
attribs =
  Verify.safe(fn ->
    [
      :wxe_util.get_const(:wx_GL_CORE_PROFILE),
      :wxe_util.get_const(:wx_GL_MAJOR_VERSION),
      4,
      :wxe_util.get_const(:wx_GL_MINOR_VERSION),
      1,
      # WX_GL_RGBA
      1,
      # WX_GL_DOUBLEBUFFER
      4,
      # WX_GL_DEPTH_SIZE, 24
      11,
      24,
      0
    ]
  end)

canvas =
  case attribs do
    list when is_list(list) ->
      case Verify.safe(fn -> :wxGLCanvas.new(frame, attribList: list) end) do
        {:error, reason} ->
          Verify.info("core-profile attribList rejected (#{reason}), falling back")
          :wxGLCanvas.new(frame)

        c ->
          Verify.ok("requested 4.1 core profile via attribList")
          c
      end

    _ ->
      Verify.info("could not resolve wx GL profile constants, using defaults")
      :wxGLCanvas.new(frame)
  end

context = :wxGLContext.new(canvas)
:wxFrame.show(frame)
true = :wxGLCanvas.setCurrent(canvas, context)

gl_string = fn const ->
  Verify.safe(fn -> :gl.getString(const) |> to_string() end)
end

version = gl_string.(OpenGL.gl_VERSION())
glsl = gl_string.(OpenGL.gl_SHADING_LANGUAGE_VERSION())
renderer = gl_string.(OpenGL.gl_RENDERER())

Verify.info("GL_VERSION   #{version}")
Verify.info("GLSL         #{glsl}")
Verify.info("GL_RENDERER  #{renderer}")

# GL_MAJOR_VERSION is a 3.0+ query. On a legacy context it errors, and
# GLCanvas.Server's `rescue` silently reports 4.1 - so check the string.
case version do
  "4." <> _ -> Verify.ok("context is OpenGL 4.x")
  other -> Verify.fail("expected a 4.x context, got #{inspect(other)}")
end

# ============================================================================
# Compile and link
# ============================================================================

Verify.section("Shaders")

shader_dir = Path.join(File.cwd!(), "priv/shaders")

programs =
  shader_dir
  |> Path.join("*.vert")
  |> Path.wildcard()
  |> Enum.map(&Path.basename(&1, ".vert"))
  |> Enum.sort()

if programs == [] do
  Verify.fail("no shaders found in priv/shaders")
end

linked =
  for name <- programs do
    vert = File.read!(Path.join(shader_dir, "#{name}.vert"))
    frag = File.read!(Path.join(shader_dir, "#{name}.frag"))

    with {:ok, vs} <- GL.create_shader(:vertex, vert),
         {:ok, fs} <- GL.create_shader(:fragment, frag),
         {:ok, program} <- GL.create_program(vs, fs) do
      GL.delete_shader(vs)
      GL.delete_shader(fs)
      Verify.ok("#{name} compiled and linked")
      {name, program}
    else
      {:error, log} ->
        Verify.fail("#{name}:\n#{log}")
        nil
    end
  end
  |> Enum.reject(&is_nil/1)

# ============================================================================
# Reflection - what the driver actually sees
# ============================================================================

Verify.section("Reflection")

for {name, program} <- linked do
  IO.puts("  #{name}:")

  block_count =
    Verify.safe(fn ->
      case :gl.getProgramiv(program, OpenGL.gl_ACTIVE_UNIFORM_BLOCKS()) do
        [n | _] -> n
        n when is_integer(n) -> n
      end
    end, 0)

  for i <- 0..max(block_count - 1, 0)//1 do
    block_name =
      Verify.safe(fn -> :gl.getActiveUniformBlockName(program, i, 256) |> to_string() end)

    size = Verify.safe(fn -> GL.get_active_uniform_block_data_size(program, i) end)
    Verify.info("uniform block [#{i}] #{inspect(block_name)} data_size=#{inspect(size)}")
  end

  uniform_count =
    Verify.safe(fn ->
      case :gl.getProgramiv(program, OpenGL.gl_ACTIVE_UNIFORMS()) do
        [n | _] -> n
        n when is_integer(n) -> n
      end
    end, 0)

  for i <- 0..max(uniform_count - 1, 0)//1 do
    case Verify.safe(fn -> :gl.getActiveUniform(program, i, 256) end) do
      {_size, _type, uname} ->
        Verify.info("uniform      [#{i}] #{inspect(to_string(uname))}")

      other ->
        Verify.info("uniform      [#{i}] #{inspect(other)}")
    end
  end
end

# ============================================================================
# std140 cross-check
# ============================================================================

Verify.section("std140")

# Mirrors the uniform blocks declared in shaders/shaders.exs. If naga ever
# changes how it lays a block out, this is where it surfaces - the driver's
# own GL_UNIFORM_BLOCK_DATA_SIZE against our computed size.
expected_layouts = [
  {"image", [row_offset: :f32, domain_min: :f32, domain_max: :f32]},
  {"line", [color: :vec4, viewport: :vec2, line_width: :f32]},
  {"grid", [line_color: :vec4, background: :vec4, spacing: :vec2, thickness: :f32]}
]

for {name, fields} <- expected_layouts do
  expected = Std140.layout(fields)

  case Enum.find(linked, fn {linked_name, _} -> linked_name == name end) do
    {_name, program} ->
      driver_size = Verify.safe(fn -> GL.get_active_uniform_block_data_size(program, 0) end)

      if driver_size == expected.size do
        Verify.ok("#{name}: #{driver_size} bytes, offsets #{inspect(Std140.offsets(expected))}")
      else
        Verify.fail(
          "#{name}: driver says #{inspect(driver_size)}, we computed #{expected.size} " <>
            "(offsets #{inspect(Std140.offsets(expected))})"
        )
      end

    nil ->
      Verify.info("#{name} not linked, skipping")
  end
end

# ============================================================================

:wxGLContext.destroy(context)
:wxFrame.destroy(frame)

if Process.get(:failed) do
  IO.puts("\n\e[31mFAILED\e[0m\n")
  System.halt(1)
else
  IO.puts("\n\e[32mAll shaders verified against #{renderer}\e[0m\n")
end
