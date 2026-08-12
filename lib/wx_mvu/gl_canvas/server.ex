defmodule WxMVU.GLCanvas.Server do
  @moduledoc false
  # Internal GenServer that manages a GLCanvas instance.
  #
  # Responsibilities:
  # - Owns the GL context
  # - Runs the render loop
  # - Routes events to the canvas module
  # - Handles data messages (bypassing MVU)
  #
  # This is started by the Renderer when it processes an :ensure_gl_canvas intent.

  use GenServer
  require Logger

  alias WxMVU.GLCanvas
  alias WxMVU.GLCanvas.Context
  alias WxMVU.GLCanvas.Event
  alias WxMVU.Renderer.ComponentRegistry

  defstruct [
    :id,
    :module,
    :wx_canvas,
    :gl_context,
    :context,
    :user_state,
    :render_scheduled,
    :fps,
    :last_render_time
  ]

  @default_fps 60

  # ============================================================================
  # Public API (called by Renderer)
  # ============================================================================

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def stop(id) do
    GenServer.stop(via_tuple(id))
  end

  defp via_tuple(id) do
    {:via, Registry, {WxMVU.GLCanvas.Registry, id}}
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    module = Keyword.fetch!(opts, :module)
    wx_canvas = Keyword.fetch!(opts, :wx_canvas)
    wx_env = Keyword.fetch!(opts, :wx_env)
    user_opts = Keyword.get(opts, :opts, [])
    fps = Keyword.get(opts, :fps, @default_fps)

    Logger.debug("GLCanvas.Server: starting #{inspect(id)} with module #{inspect(module)}")

    # Set wx environment in this process
    :wx.set_env(wx_env)

    # Initialize the GL NIF in this process where that entry point exists.
    # Absent on OTP 29 / wx-2.6, where the NIF initialises itself.
    Code.ensure_loaded(:gl)

    if function_exported?(:gl, :init_nif, 0) do
      try do
        apply(:gl, :init_nif, [])
      catch
        _, _ -> :ok
      end
    end

    # Register for data routing
    ComponentRegistry.register({:gl_canvas, id}, self())

    # Create GL context and make it current
    gl_context = create_gl_context(wx_canvas)
    make_current(wx_canvas, gl_context)

    # Build context struct with GL info
    context = build_context(wx_canvas)

    # Initialize user module
    case module.init(context, user_opts) do
      {:ok, user_state} ->
        state = %__MODULE__{
          id: id,
          module: module,
          wx_canvas: wx_canvas,
          gl_context: gl_context,
          context: context,
          user_state: user_state,
          render_scheduled: false,
          fps: fps,
          last_render_time: nil
        }

        # Schedule first render
        state = schedule_render(state)

        {:ok, state}

      {:error, reason} ->
        Logger.error("GLCanvas.Server: init failed for #{inspect(id)}: #{inspect(reason)}")
        {:stop, {:init_failed, reason}}
    end
  end

  @impl true
  def handle_info(:render_tick, state) do
    state = %{state | render_scheduled: false}

    # Make context current
    make_current(state.wx_canvas, state.gl_context)

    # Call user render
    {:noreply, user_state} = state.module.render(state.user_state)

    # Swap buffers
    swap_buffers(state.wx_canvas)

    # Schedule next render
    state = %{state | user_state: user_state, last_render_time: System.monotonic_time(:millisecond)}
    state = schedule_render(state)

    {:noreply, state}
  end

  def handle_info(:request_render, state) do
    # Force immediate render on next tick
    state = schedule_render(state)
    {:noreply, state}
  end

  def handle_info({:gl_data, msg}, state) do
    # Data message - route to handle_data
    {:noreply, user_state} = state.module.handle_data(msg, state.user_state)
    {:noreply, %{state | user_state: user_state}}
  end

  def handle_info({:wx_resize, logical_size, pixel_size, dpi_scale}, state) do
    # Resize event from wx
    make_current(state.wx_canvas, state.gl_context)

    event = %Event.Resize{
      logical_size: logical_size,
      pixel_size: pixel_size,
      dpi_scale: dpi_scale
    }

    # Update context
    context = %{state.context |
      logical_size: logical_size,
      pixel_size: pixel_size,
      dpi_scale: dpi_scale
    }

    # Call user handler
    {:noreply, user_state} = state.module.handle_event(event, state.user_state)

    {:noreply, %{state | context: context, user_state: user_state}}
  end

  def handle_info({:wx_mouse, type, x, y, button, wheel_delta, modifiers}, state) do
    event = %Event.Mouse{
      type: type,
      x: x,
      y: y,
      button: button,
      wheel_delta: wheel_delta,
      modifiers: modifiers
    }

    {:noreply, user_state} = state.module.handle_event(event, state.user_state)
    {:noreply, %{state | user_state: user_state}}
  end

  def handle_info({:wx_key, type, key, char, modifiers}, state) do
    event = %Event.Key{
      type: type,
      key: key,
      char: char,
      modifiers: modifiers
    }

    {:noreply, user_state} = state.module.handle_event(event, state.user_state)
    {:noreply, %{state | user_state: user_state}}
  end

  def handle_info({:wx_focus, type}, state) do
    event = %Event.Focus{type: type}

    {:noreply, user_state} = state.module.handle_event(event, state.user_state)
    {:noreply, %{state | user_state: user_state}}
  end

  def handle_info(msg, state) do
    Logger.debug("GLCanvas.Server: unhandled message #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("GLCanvas.Server: terminating #{inspect(state.id)}: #{inspect(reason)}")

    # Make context current for cleanup
    make_current(state.wx_canvas, state.gl_context)

    # Call user terminate
    state.module.terminate(reason, state.user_state)

    # Unregister
    ComponentRegistry.unregister({:gl_canvas, state.id})

    # Destroy GL context
    destroy_gl_context(state.gl_context)

    :ok
  end

  # ============================================================================
  # Render Scheduling
  # ============================================================================

  defp schedule_render(%{render_scheduled: true} = state), do: state

  defp schedule_render(state) do
    interval = div(1000, state.fps)
    Process.send_after(self(), :render_tick, interval)
    %{state | render_scheduled: true}
  end

  # ============================================================================
  # GL Context Management
  # ============================================================================

  defp create_gl_context(wx_canvas) do
    # Create GL context for the canvas
    # wxGLContext.new(canvas)
    :wxGLContext.new(wx_canvas)
  end

  defp destroy_gl_context(gl_context) do
    :wxGLContext.destroy(gl_context)
  end

  defp make_current(wx_canvas, gl_context) do
    :wxGLCanvas.setCurrent(wx_canvas, gl_context)
  end

  defp swap_buffers(wx_canvas) do
    :wxGLCanvas.swapBuffers(wx_canvas)
  end

  defp build_context(wx_canvas) do
    # Query GL version and capabilities
    {gl_major, gl_minor} = get_gl_version()
    glsl_version = get_glsl_version()
    {logical_w, logical_h} = get_canvas_size(wx_canvas)
    dpi_scale = get_dpi_scale(wx_canvas)
    pixel_w = trunc(logical_w * dpi_scale)
    pixel_h = trunc(logical_h * dpi_scale)

    Logger.debug("GLCanvas.Server: OpenGL #{gl_major}.#{gl_minor}, GLSL #{glsl_version}")
    warn_unless_supported({gl_major, gl_minor})

    %Context{
      gl_version: {gl_major, gl_minor},
      glsl_version: glsl_version,
      profile: :core,
      logical_size: {logical_w, logical_h},
      pixel_size: {pixel_w, pixel_h},
      dpi_scale: dpi_scale,
      capabilities: query_capabilities()
    }
  end

  # GL_MAJOR_VERSION / GL_MINOR_VERSION are themselves OpenGL 3.0+ queries. On a
  # legacy context they do not raise - they return uninitialised memory, so no
  # rescue can catch them and the old fallback to {4, 1} never fired. Observed
  # values on a 2.1 context: -104284064 and 1402814560 across two runs.
  #
  # The GL_VERSION string is available on every profile and every version, and
  # its first two components are the version by specification.
  defp get_gl_version do
    parse_gl_version(get_version_string())
  end

  defp get_version_string do
    alias WxEx.Constants.OpenGL
    :gl.getString(OpenGL.gl_VERSION()) |> to_string()
  rescue
    _ -> ""
  catch
    _, _ -> ""
  end

  # "4.1 Metal - 90.5", "4.6.0 NVIDIA 550.54.14", "2.1 Metal - 90.5"
  defp parse_gl_version(string) do
    case Regex.run(~r/^\s*(\d+)\.(\d+)/, string) do
      [_, major, minor] -> {String.to_integer(major), String.to_integer(minor)}
      _ -> {0, 0}
    end
  end

  defp get_glsl_version do
    alias WxEx.Constants.OpenGL
    :gl.getString(OpenGL.gl_SHADING_LANGUAGE_VERSION()) |> to_string()
  rescue
    _ -> "4.10"
  catch
    _, _ -> "4.10"
  end

  # wx_mvu ships GLSL 410 shaders, so anything below 4.1 cannot run them. The
  # symptom is otherwise a wall of "version '410' is not supported" syntax
  # errors from the driver, which does not point at the cause.
  defp warn_unless_supported({major, _minor}) when major >= 4, do: :ok

  defp warn_unless_supported({0, 0}) do
    Logger.warning(
      "GLCanvas.Server: could not determine the OpenGL version. If shaders fail " <>
        "to compile, check the attribList in Renderer.Intents.GLCanvas."
    )
  end

  defp warn_unless_supported({major, minor}) do
    Logger.warning(
      "GLCanvas.Server: got an OpenGL #{major}.#{minor} context, but wx_mvu " <>
        "shaders require 4.1 core. Shader compilation will fail. The core " <>
        "profile is requested via attribList in Renderer.Intents.GLCanvas."
    )
  end

  defp get_canvas_size(wx_canvas) do
    :wxWindow.getSize(wx_canvas)
  end

  defp get_dpi_scale(wx_canvas) do
    # Try to get DPI scale factor
    # On some platforms this may not be available
    try do
      :wxWindow.getContentScaleFactor(wx_canvas)
    rescue
      _ -> 1.0
    catch
      _, _ -> 1.0
    end
  end

  defp default_capabilities do
    %{
      max_texture_size: 16384,
      max_texture_units: 16,
      max_vertex_attribs: 16,
      max_uniform_locations: 1024,
      max_renderbuffer_size: 16384,
      max_viewport_dims: {16384, 16384},
      max_uniform_block_size: 16384,
      max_uniform_buffer_bindings: 36,
      uniform_buffer_offset_alignment: 256
    }
  end

  defp query_capabilities do
    alias WxEx.Constants.OpenGL

    %{
      max_texture_size: get_integer(OpenGL.gl_MAX_TEXTURE_SIZE()),
      max_texture_units: get_integer(OpenGL.gl_MAX_TEXTURE_IMAGE_UNITS()),
      max_vertex_attribs: get_integer(OpenGL.gl_MAX_VERTEX_ATTRIBS()),
      # GL_MAX_UNIFORM_LOCATIONS is GL 4.3+. macOS caps at 4.1, so this query
      # fails there and reports 0. Kept for platforms that do support it.
      max_uniform_locations: get_integer(OpenGL.gl_MAX_UNIFORM_LOCATIONS()),
      max_renderbuffer_size: get_integer(OpenGL.gl_MAX_RENDERBUFFER_SIZE()),
      max_viewport_dims: get_integer_pair(OpenGL.gl_MAX_VIEWPORT_DIMS()),
      # Uniform buffer limits. The offset alignment constrains where a
      # bind_buffer_range sub-range may start, and is commonly 256.
      max_uniform_block_size: get_integer(OpenGL.gl_MAX_UNIFORM_BLOCK_SIZE()),
      max_uniform_buffer_bindings: get_integer(OpenGL.gl_MAX_UNIFORM_BUFFER_BINDINGS()),
      uniform_buffer_offset_alignment:
        get_integer(OpenGL.gl_UNIFORM_BUFFER_OFFSET_ALIGNMENT())
    }
  rescue
    _ -> default_capabilities()
  catch
    _, _ -> default_capabilities()
  end

  defp get_integer(pname) do
    case :gl.getIntegerv(pname) do
      [value | _] -> value
      _ -> 0
    end
  rescue
    _ -> 0
  catch
    _, _ -> 0
  end

  defp get_integer_pair(pname) do
    case :gl.getIntegerv(pname) do
      [a, b | _] -> {a, b}
      [a] -> {a, a}
      _ -> {16384, 16384}
    end
  rescue
    _ -> {16384, 16384}
  catch
    _, _ -> {16384, 16384}
  end

end
