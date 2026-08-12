defmodule WxMVU.Visual.Host do
  @moduledoc false
  # Adapts a `WxMVU.Visual` onto the `WxMVU.GLCanvas` behaviour.
  #
  # A visual needs a GL context, a render loop, resize events and a place in the
  # widget tree — all of which GLCanvas.Server already provides. Rather than
  # building a second runtime alongside it, `{:ensure_visual, ...}` creates an
  # ordinary GL canvas whose module is this one, and this delegates.
  #
  # So a visual is not a new kind of thing in the renderer; it is a canvas whose
  # contents happen to be declared rather than hand-drawn.

  use WxMVU.GLCanvas

  alias WxMVU.Renderer.GL
  alias WxMVU.Visual.Frame

  @impl true
  def init(ctx, opts) do
    module = Keyword.fetch!(opts, :visual)
    visual_opts = Keyword.fetch!(opts, :visual_opts)
    clear = Keyword.get(opts, :clear, {0.0, 0.0, 0.0, 1.0})

    {width, height} = ctx.pixel_size
    GL.viewport(0, 0, width, height)

    case module.init(ctx, visual_opts) do
      {:ok, visual} ->
        {:ok, %{module: module, visual: visual, opts: visual_opts, ctx: ctx, clear: clear}}

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

    {:noreply, %{host | ctx: ctx}}
  end

  def handle_event(_event, host), do: {:noreply, host}

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
    GL.clear(:color)

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
