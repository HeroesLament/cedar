defmodule Cedar.GLCase do
  @moduledoc """
  Test case for anything needing a real OpenGL 4.1 core context.

      use Cedar.GLCase

  Tags the module `:gl`, which `test_helper.exs` excludes by default — these
  need a display, so they run explicitly:

      mix test --only gl

  Provides a current context per test, an offscreen framebuffer helper, and
  pixel readback.

  ## Why the context is made current in `setup` and not `setup_all`

  A GL context is bound to the process that made it current, and ExUnit runs
  each test in its own process. Creating the context once in `setup_all` and
  relying on it in tests silently fails: the calls go nowhere.

  There is also deliberately no teardown. wx releases the frame and context
  with the process that owns them, and ExUnit runs `on_exit` callbacks after
  the wx server has already gone — an explicit destroy there dies with
  `{:wx, :unknown_env}`, or with a dead gen_server if it tries to re-register.
  """

  use ExUnit.CaseTemplate

  alias Cedar.Renderer.GL

  using do
    quote do
      @moduletag :gl

      import Cedar.GLCase

      alias Cedar.GLCanvas.Draw.{Colormap, Geometry, Program, Texture}
      alias Cedar.Renderer.GL
    end
  end

  setup_all do
    _wx = :wx.new()
    frame = :wxFrame.new(:wx.null(), -1, ~c"cedar tests", size: {160, 120})

    # An explicit core-profile request. Without it macOS hands back a legacy
    # 2.1 context in which none of cedar's shaders will even compile.
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

    %{env: :wx.get_env(), canvas: canvas, context: context}
  end

  setup %{env: env, canvas: canvas, context: context} do
    :wx.set_env(env)
    true = :wxGLCanvas.setCurrent(canvas, context)
    :ok
  end

  @doc """
  Creates and binds a square RGBA8 framebuffer, and sets the viewport to match.

  Returns the framebuffer object. Tests read from it with `pixel/3` or
  `red_channel/1`.

  ## Options

    * `:depth` - attach a depth buffer, default `false`

  Without a depth attachment the depth test *passes unconditionally* rather
  than failing — GL has nothing to compare against — so a 3D test that forgets
  it still draws something, just with the far faces of the model painted over
  the near ones. Anything asserting on solid geometry wants `depth: true`.
  """
  def offscreen(size, opts \\ [])

  def offscreen(size, opts) do
    target = GL.create_texture()
    GL.bind_texture(:texture_2d, target)

    GL.tex_image_2d(
      size,
      size,
      :rgba8,
      :rgba,
      :unsigned_byte,
      :binary.copy(<<0>>, size * size * 4)
    )

    GL.tex_parameter(:min_filter, :nearest)
    GL.tex_parameter(:mag_filter, :nearest)

    fbo = GL.create_framebuffer()
    GL.bind_framebuffer(:both, fbo)
    GL.framebuffer_texture_2d(:color, 0, target)

    if Keyword.get(opts, :depth, false) do
      rbo = GL.create_renderbuffer()
      GL.bind_renderbuffer(rbo)
      GL.renderbuffer_storage(:depth24_stencil8, size, size)
      GL.framebuffer_renderbuffer(:depth_stencil, rbo)
    end

    ExUnit.Assertions.assert(GL.check_framebuffer_status() == :complete)

    GL.viewport(0, 0, size, size)
    fbo
  end

  @doc "Clears the bound framebuffer to opaque black."
  def clear do
    GL.clear_color(0.0, 0.0, 0.0, 1.0)
    GL.clear(:color)
  end

  @doc "Packs numbers as native-endian f32, the format every vertex buffer uses."
  def floats(values), do: for(v <- values, into: <<>>, do: <<v * 1.0::float-32-native>>)

  @doc """
  Reads one pixel as `{r, g, b}`.

  Rows come back bottom-up, as GL delivers them: row 0 is the bottom of the
  framebuffer, not the top.
  """
  def pixel(size, col, row) do
    pixels = GL.read_pixels(0, 0, size, size, :rgba, :unsigned_byte)
    offset = (row * size + col) * 4
    <<_::binary-size(offset), r, g, b, _a, _::binary>> = pixels
    {r, g, b}
  end

  @doc "Reads the red channel of every pixel, for distribution assertions."
  def red_channel(size) do
    pixels = GL.read_pixels(0, 0, size, size, :rgba, :unsigned_byte)

    for i <- 0..(size * size - 1) do
      offset = i * 4
      <<_::binary-size(offset), r, _g, _b, _a, _::binary>> = pixels
      r
    end
  end

  @doc """
  Uploads vertex data into a fresh vertex array, returning `{vao, vbo}`.

  Raw rather than via `Geometry`, so tests that are checking a `Program`'s own
  layout handling do not route through another layer that could mask a fault.
  """
  def buffer(data) do
    vao = GL.create_vertex_array()
    vbo = GL.create_buffer()
    GL.bind_vertex_array(vao)
    GL.bind_buffer(:array, vbo)
    GL.buffer_data(:array, data, :static)
    {vao, vbo}
  end

  @doc "Vertices for a clip-space quad with texture coordinates, as a strip."
  def quad_vertices do
    floats([
      -1.0,
      -1.0,
      0.0,
      0.0,
      1.0,
      -1.0,
      1.0,
      0.0,
      -1.0,
      1.0,
      0.0,
      1.0,
      1.0,
      1.0,
      1.0,
      1.0
    ])
  end

  @doc "Approximate equality for 8-bit channel values."
  def close?(a, b, tolerance \\ 6), do: abs(a - b) <= tolerance
end
