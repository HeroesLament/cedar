defmodule Cedar.Visual.Layers do
  @moduledoc """
  Several visuals drawn into one canvas, in order.

      {:ensure_visual, :waterfall, :layers, :root,
        layers: [
          history: {:image, grid: {1024, 512}, domain: {-100.0, 0.0},
                    colormap: :turbo, advance: :per_datum},
          ticks: {:line, color: {0.75, 0.75, 0.78, 1.0}, width: 1.0}
        ]}

  Almost every real display is more than one thing: a waterfall with a
  frequency ruler over it, a plot with gridlines under its trace and labels
  beside it, a CAD viewport with a ground plane under the model. Before this,
  the second thing meant abandoning visuals and hand-rolling a `GLCanvas` that
  reimplemented the first thing badly — which is exactly what
  `NzScope.Canvas.Waterfall` was.

  Layers draw in declaration order, so the list reads back to front.

  ## Addressing a layer

  Data is routed by layer name:

      Cedar.Visual.send_data(:waterfall, {:history, {:row, bins}})
      Cedar.Visual.send_data(:waterfall, {:ticks, {:polylines, runs}})

  Configuration likewise, through the ordinary MVU diff — a changed layer
  declaration reaches only that layer:

      {:ensure_visual, :waterfall, :layers, :root,
        layers: [
          history: {:image, ..., domain: {model.db_floor, model.db_ceiling}},
          ticks: {:line, ...}
        ]}

  Changing `db_floor` there is one uniform write to the image layer. The line
  layer is not told, not rebuilt, and its buffer is not touched.

  ## What this deliberately is not

  It is not a scene graph. There are no transforms, no parents, no z-ordering
  beyond the order you wrote, and no per-layer viewport. Layers share the
  framebuffer and the frame, and each one draws over whatever the last left
  behind. That is enough for overlays, which is the entire problem it exists
  to solve; anything more belongs in a `Viewport` with a camera, not here.

  ## Options

    * `:layers` - required, a keyword list of `name -> {type, opts}` where
      `type` is a built-in visual atom, or `{module, opts}` for your own

  A layer name may be any atom, and the same visual type may appear more than
  once under different names — two traces on one plot is `trace_a` and
  `trace_b`, both `:line`.
  """

  use Cedar.Visual

  alias Cedar.Visual

  defstruct [:layers]

  @impl true
  def init(ctx, opts) do
    declarations = fetch_layers!(opts)

    # Built in order so that a failure part-way can release what came before
    # it. A half-initialized layer stack would otherwise leak a program and a
    # texture per attempt, and an application retrying a canvas on resize can
    # attempt a lot.
    Enum.reduce_while(declarations, {:ok, []}, fn {name, module, layer_opts}, {:ok, built} ->
      case module.init(ctx, layer_opts) do
        {:ok, state} ->
          {:cont, {:ok, [{name, module, state} | built]}}

        {:error, reason} ->
          Enum.each(built, fn {_name, module, state} -> module.destroy(state) end)
          {:halt, {:error, {:layer_failed, name, reason}}}
      end
    end)
    |> case do
      {:ok, built} -> {:ok, %__MODULE__{layers: Enum.reverse(built)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update(state, opts) do
    declarations = fetch_layers!(opts)

    if Enum.map(declarations, &elem(&1, 0)) != names(state) do
      # Adding, removing or reordering layers changes what the canvas *is*.
      # Rebuilding is both simpler and more honest than trying to reconcile it
      # in place, and it is not on any hot path - the layer list comes from
      # code, not from data.
      {:reinit, :layers_changed}
    else
      state.layers
      |> Enum.zip(declarations)
      |> Enum.reduce_while({:ok, []}, fn {{name, module, layer_state}, {name, _module, opts}},
                                         {:ok, done} ->
        case module.update(layer_state, opts) do
          {:ok, updated} -> {:cont, {:ok, [{name, module, updated} | done]}}
          {:reinit, reason} -> {:halt, {:reinit, {name, reason}}}
        end
      end)
      |> case do
        {:ok, updated} -> {:ok, %{state | layers: Enum.reverse(updated)}}
        {:reinit, reason} -> {:reinit, reason}
      end
    end
  end

  @impl true
  def handle_data(state, {name, message}) when is_atom(name) do
    case Enum.find_index(state.layers, fn {layer, _module, _state} -> layer == name end) do
      nil ->
        # Dropped rather than raised. This is the high-rate path, and a
        # producer that outlives a layer - or starts before one exists - is a
        # normal condition in a supervised system, not a bug worth crashing a
        # canvas over.
        {:ok, state}

      index ->
        {layer, module, layer_state} = Enum.at(state.layers, index)
        {:ok, updated} = module.handle_data(layer_state, message)

        {:ok, %{state | layers: List.replace_at(state.layers, index, {layer, module, updated})}}
    end
  end

  def handle_data(state, _other), do: {:ok, state}

  @impl true
  def draw(state, frame) do
    layers =
      Enum.map(state.layers, fn {name, module, layer_state} ->
        {:ok, drawn} = module.draw(layer_state, frame)
        {name, module, drawn}
      end)

    {:ok, %{state | layers: layers}}
  end

  @impl true
  def destroy(state) do
    Enum.each(state.layers, fn {_name, module, layer_state} -> module.destroy(layer_state) end)
    :ok
  end

  @doc "Layer names, in draw order."
  @spec names(%__MODULE__{}) :: [atom()]
  def names(%__MODULE__{layers: layers}), do: Enum.map(layers, &elem(&1, 0))

  # ==========================================================================

  @doc false
  def fetch_layers!(opts) do
    case Keyword.get(opts, :layers) do
      nil ->
        raise ArgumentError, ":layers is required, as a keyword list of name -> {type, opts}"

      [] ->
        raise ArgumentError, ":layers is empty; a stack of nothing draws nothing"

      layers when is_list(layers) ->
        unless Keyword.keyword?(layers) do
          raise ArgumentError,
                ":layers must be a keyword list of name -> {type, opts}, got #{inspect(layers)}"
        end

        names = Keyword.keys(layers)

        case names -- Enum.uniq(names) do
          [] -> :ok
          dupes -> raise ArgumentError, "duplicate layer names: #{inspect(Enum.uniq(dupes))}"
        end

        Enum.map(layers, fn {name, declaration} -> normalize(name, declaration) end)

      other ->
        raise ArgumentError, ":layers must be a keyword list, got #{inspect(other)}"
    end
  end

  defp normalize(name, {module, opts}) when is_atom(module) and is_list(opts) do
    resolved =
      if Code.ensure_loaded?(module) and function_exported?(module, :init, 2) do
        module
      else
        Visual.resolve(module)
      end

    {name, resolved, opts}
  end

  defp normalize(name, type) when is_atom(type), do: {name, Visual.resolve(type), []}

  defp normalize(name, other) do
    raise ArgumentError,
          "layer #{inspect(name)} must be a visual type or {type, opts}, got #{inspect(other)}"
  end
end
