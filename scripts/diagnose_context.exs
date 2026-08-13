# A/B diagnostic: does Intents.GLCanvas actually get the context it requests?
#
# It passes an attribList with hardcoded integers for WX_GL_CORE_PROFILE,
# WX_GL_MAJOR_VERSION and WX_GL_MINOR_VERSION. But wx.hrl defines those three
# as `wxe_util:get_const/1` lookups, i.e. resolved at runtime per wx build -
# unlike WX_GL_RGBA/DOUBLEBUFFER/DEPTH_SIZE, which really are fixed integers.
#
# If the hardcoded values are wrong, wx silently ignores the profile request
# and hands back a legacy context in which `#version 410 core` cannot compile.
#
#     mix run scripts/diagnose_context.exs

alias Cedar.Renderer.GL
alias WxEx.Constants.OpenGL

_wx = :wx.new()

# Verbatim from lib/cedar/renderer/intents/gl_canvas.ex
hardcoded = [
  1,
  4,
  11,
  24,
  12,
  8,
  20,
  21,
  4,
  22,
  1,
  0
]

const = fn name ->
  try do
    :wxe_util.get_const(name)
  rescue
    _ -> :unavailable
  catch
    _, _ -> :unavailable
  end
end

core = const.(:wx_GL_CORE_PROFILE)
major = const.(:wx_GL_MAJOR_VERSION)
minor = const.(:wx_GL_MINOR_VERSION)

IO.puts("\n\e[1mRuntime wx GL constants on this build\e[0m")
IO.puts("  WX_GL_CORE_PROFILE   runtime=#{inspect(core)}   hardcoded=20")
IO.puts("  WX_GL_MAJOR_VERSION  runtime=#{inspect(major)}   hardcoded=21")
IO.puts("  WX_GL_MINOR_VERSION  runtime=#{inspect(minor)}   hardcoded=22")

resolved = [1, 4, 11, 24, 12, 8, core, major, 4, minor, 1, 0]

probe_shader = """
#version 410 core
layout(location = 0) in vec2 a_position;
void main() { gl_Position = vec4(a_position, 0.0, 1.0); }
"""

probe = fn label, attribs ->
  IO.puts("\n\e[1m#{label}\e[0m")
  frame = :wxFrame.new(:wx.null(), -1, ~c"probe", size: {120, 80})

  canvas =
    case attribs do
      nil -> :wxGLCanvas.new(frame)
      list -> :wxGLCanvas.new(frame, attribList: list)
    end

  context = :wxGLContext.new(canvas)
  :wxFrame.show(frame)
  :wxGLCanvas.setCurrent(canvas, context)

  str = fn c -> :gl.getString(c) |> to_string() end
  IO.puts("  GL_VERSION  #{str.(OpenGL.gl_VERSION())}")
  IO.puts("  GLSL        #{str.(OpenGL.gl_SHADING_LANGUAGE_VERSION())}")

  reported =
    try do
      case :gl.getIntegerv(OpenGL.gl_MAJOR_VERSION()) do
        [v | _] -> v
        v -> v
      end
    rescue
      e -> {:raised, Exception.message(e)}
    catch
      _, _ -> :threw
    end

  IO.puts("  GL_MAJOR_VERSION query -> #{inspect(reported)}  (what build_context/1 trusts)")

  case GL.create_shader(:vertex, probe_shader) do
    {:ok, shader} ->
      GL.delete_shader(shader)
      IO.puts("  \e[32m#version 410 core compiles\e[0m")

    {:error, log} ->
      IO.puts("  \e[31m#version 410 core REJECTED\e[0m")
      log |> String.trim() |> String.split("\n") |> Enum.each(&IO.puts("    #{&1}"))
  end

  :wxGLContext.destroy(context)
  :wxFrame.destroy(frame)
end

probe.("A. no attribList at all (baseline)", nil)
probe.("B. the hardcoded attribList currently shipping", hardcoded)
probe.("C. the same list with runtime-resolved constants", resolved)

IO.puts("\n\e[1mD. :gl.init_nif/0\e[0m")
exported? = :erlang.function_exported(:gl, :init_nif, 0)
IO.puts("  exported? #{exported?}")

IO.puts(
  "  GL calls above worked regardless, so the \"OpenGL NIF initialization failed\"\n" <>
    "  warning is #{if exported?, do: "meaningful", else: "spurious on this OTP"}.\n"
)
