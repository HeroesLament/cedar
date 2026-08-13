defmodule Cedar.Renderer.Intents.Visual do
  @moduledoc false
  # Intent handler for declared visuals.
  #
  # A visual is hosted by an ordinary GL canvas — see `Cedar.Visual.Host` — so
  # this mostly translates a visual declaration into a canvas declaration and
  # hands it to the existing handler. Creation, destruction, event wiring and
  # the render loop are all reused rather than reimplemented.

  require Logger

  alias Cedar.GLCanvas
  alias Cedar.Renderer.Intents.GLCanvas, as: GLCanvasIntent
  alias Cedar.Visual

  # Options belonging to the host rather than the visual, stripped before the
  # rest is passed through as the visual's declaration.
  @host_opts [:size, :fps, :clear, :module, :opts, :notify]

  def apply({:ensure_visual, id, type, parent_id, opts}, state) do
    {module, visual_opts} = resolve(type, opts)

    canvas_opts = [
      module: Cedar.Visual.Host,
      size: Keyword.get(opts, :size, {640, 480}),
      fps: Keyword.get(opts, :fps, 60),
      opts: [
        visual: module,
        visual_opts: visual_opts,
        visual_id: id,
        notify: Keyword.get(opts, :notify),
        clear: Keyword.get(opts, :clear, {0.0, 0.0, 0.0, 1.0})
      ]
    ]

    GLCanvasIntent.apply({:ensure_gl_canvas, id, parent_id, canvas_opts}, state)
  end

  def apply({:update_visual, id, type, opts}, state) do
    {_module, visual_opts} = resolve(type, opts)

    # Delivered as data rather than as a renderer call, because the visual's
    # state lives in the canvas process and only that process has the context
    # current.
    GLCanvas.send_data(id, {:visual_update, visual_opts})
    state
  end

  def apply({:destroy_visual, id}, state) do
    GLCanvasIntent.apply({:destroy_gl_canvas, id}, state)
  end

  # ==========================================================================

  defp resolve(:custom, opts) do
    module =
      Keyword.get(opts, :module) ||
        raise ArgumentError, ":custom visuals require module: YourVisualModule"

    {module, Keyword.get(opts, :opts, [])}
  end

  defp resolve(type, opts) when is_atom(type) do
    if Keyword.has_key?(opts, :opts) do
      raise ArgumentError, """
      #{inspect(type)} is a built-in visual, so its options go inline:

          {:ensure_visual, :id, #{inspect(type)}, :parent, grid: {512, 256}, ...}

      `opts:` is for :custom visuals, where it separates your module's options
      from the host's. Passing it to a built-in one would silently drop
      everything inside it.
      """
    end

    {Visual.resolve(type), Keyword.drop(opts, @host_opts)}
  end
end
