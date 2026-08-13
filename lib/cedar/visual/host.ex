defmodule Cedar.Visual.Host do
  @moduledoc false
  # Adapts a `Cedar.Visual` onto the `Cedar.GLCanvas` behaviour.
  #
  # A visual needs a GL context, a render loop, resize events and a place in the
  # widget tree — all of which GLCanvas.Server already provides. Rather than
  # building a second runtime alongside it, `{:ensure_visual, ...}` creates an
  # ordinary GL canvas whose module is this one, and this delegates.
  #
  # So a visual is not a new kind of thing in the renderer; it is a canvas whose
  # contents happen to be declared rather than hand-drawn.

  use Cedar.GLCanvas

  alias Cedar.GLCanvas.Event.Mouse
  alias Cedar.Renderer.GL
  alias Cedar.Visual.Frame

  @impl true
  def init(ctx, opts) do
    module = Keyword.fetch!(opts, :visual)
    visual_opts = Keyword.fetch!(opts, :visual_opts)
    clear = Keyword.get(opts, :clear, {0.0, 0.0, 0.0, 1.0})
    id = Keyword.get(opts, :visual_id)
    notify = Keyword.get(opts, :notify)

    {width, height} = ctx.pixel_size
    GL.viewport(0, 0, width, height)

    case module.init(ctx, visual_opts) do
      {:ok, visual} ->
        {:ok,
         %{
           module: module,
           visual: visual,
           opts: visual_opts,
           ctx: ctx,
           clear: clear,
           id: id,
           notify: notify
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_event(%Resize{pixel_size: {width, height}} = event, host) do
    GL.viewport(0, 0, width, height)

    ctx = %{
      host.ctx
      | pixel_size: event.pixel_size,
        logical_size: event.logical_size,
        dpi_scale: event.dpi_scale
    }

    if is_pid(host.notify) do
      # A scene laying content out in surface coordinates needs the surface
      # size, and it is the one thing view/1 cannot derive from the model.
      # Reporting it makes the size part of the model like anything else.
      send(
        host.notify,
        {:ui_event, host.id, :resize,
         %{
           pixel_size: event.pixel_size,
           logical_size: event.logical_size,
           dpi_scale: event.dpi_scale
         }}
      )
    end

    {:noreply, %{host | ctx: ctx}}
  end

  def handle_event(%Mouse{} = event, %{notify: pid} = host) when is_pid(pid) do
    {width, height} = host.ctx.pixel_size
    scale = host.ctx.dpi_scale || 1.0

    # Both forms, because callers need different ones and neither is
    # reconstructible from the other without knowing the DPI scale: `x`/`y` are
    # wx's logical pixels, which is what a hit test against a widget layout
    # wants, and `u`/`v` are the fraction across the surface, which is what a
    # hit test against *content* wants and which survives a resize.
    payload = %{
      type: event.type,
      button: event.button,
      x: event.x,
      y: event.y,
      u: clamp_unit(event.x * scale / max(width, 1)),
      v: clamp_unit(event.y * scale / max(height, 1)),
      wheel_delta: event.wheel_delta,
      modifiers: event.modifiers,
      pixel_size: host.ctx.pixel_size
    }

    send(pid, {:ui_event, host.id, :mouse, payload})
    {:noreply, host}
  end

  def handle_event(_event, host), do: {:noreply, host}

  defp clamp_unit(t) when t < 0.0, do: 0.0
  defp clamp_unit(t) when t > 1.0, do: 1.0
  defp clamp_unit(t), do: t

  @impl true
  def handle_data({:visual_update, opts}, host) do
    case host.module.update(host.visual, opts) do
      {:ok, visual} ->
        {:noreply, %{host | visual: visual, opts: opts}}

      {:reinit, _reason} ->
        # The visual has decided the change is not worth handling incrementally
        # — a resized grid, say, where keeping the old contents would smear
        # history across new dimensions. Rebuild rather than pretend.
        host.module.destroy(host.visual)

        case host.module.init(host.ctx, opts) do
          {:ok, visual} ->
            {:noreply, %{host | visual: visual, opts: opts}}

          {:error, reason} ->
            raise "reinitialising #{inspect(host.module)} failed: #{inspect(reason)}"
        end
    end
  end

  def handle_data(message, host) do
    {:ok, visual} = host.module.handle_data(host.visual, message)
    {:noreply, %{host | visual: visual}}
  end

  @impl true
  def render(host) do
    {r, g, b, a} = host.clear
    GL.clear_color(r, g, b, a)

    # Colour *and* depth. A visual that draws 3D geometry leaves depth values
    # behind, and without clearing them the second frame is tested against the
    # first - so the model renders correctly once and then progressively eats
    # itself. Harmless on a canvas with no depth attachment.
    GL.clear(:color)
    GL.clear(:depth)

    frame = %Frame{
      pixel_size: host.ctx.pixel_size,
      logical_size: host.ctx.logical_size,
      dpi_scale: host.ctx.dpi_scale
    }

    {:ok, visual} = host.module.draw(host.visual, frame)
    {:noreply, %{host | visual: visual}}
  end

  @impl true
  def terminate(_reason, host) do
    host.module.destroy(host.visual)
    :ok
  end
end
