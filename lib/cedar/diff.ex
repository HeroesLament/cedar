defmodule Cedar.Diff do
  @moduledoc """
  Computes minimal changeset between intent lists.
  """

  @type intent :: tuple()
  @type intent_id :: term()

  @spec compute(old_intents :: [intent()], new_intents :: [intent()]) :: [intent()]
  def compute(old_intents, new_intents) do
    old_index = index_intents(old_intents)
    new_index = index_intents(new_intents)

    old_ids = MapSet.new(Map.keys(old_index))
    new_ids = MapSet.new(Map.keys(new_index))

    removed_ids = MapSet.difference(old_ids, new_ids)
    added_ids = MapSet.difference(new_ids, old_ids)
    common_ids = MapSet.intersection(old_ids, new_ids)

    # Preserve topological order from new_intents for creates
    destroy_intents = build_destroy_intents(removed_ids, old_index)
    create_intents = build_create_intents(added_ids, new_intents)
    update_intents = build_update_intents(common_ids, old_index, new_index)
    action_intents = extract_action_intents(new_intents)

    # Split updates: widget/panel/window updates before property sets
    {structural_updates, property_updates} = Enum.split_with(update_intents, &structural_update?/1)

    destroy_intents ++ create_intents ++ structural_updates ++ property_updates ++ action_intents
  end

  ## ------------------------------------------------------------------
  ## Structural vs property updates
  ## ------------------------------------------------------------------

  defp structural_update?({:update_widget, _, _, _}), do: true
  defp structural_update?({:update_panel, _, _}), do: true
  defp structural_update?({:update_window, _, _}), do: true
  defp structural_update?({:layout, _, _}), do: true
  defp structural_update?(_), do: false

  ## ------------------------------------------------------------------
  ## Indexing
  ## ------------------------------------------------------------------

  @spec index_intents([intent()]) :: %{intent_id() => intent()}
  def index_intents(intents) do
    intents
    |> Enum.filter(&diffable?/1)
    |> Map.new(fn intent -> {intent_id(intent), intent} end)
  end

  ## ------------------------------------------------------------------
  ## Intent identity
  ## ------------------------------------------------------------------

  @spec intent_id(intent()) :: intent_id()
  def intent_id({:ensure_window, id, _opts}), do: {:window, id}
  def intent_id({:ensure_panel, id, _parent, _opts}), do: {:panel, id}
  def intent_id({:ensure_widget, id, type, _parent, _opts}), do: {:widget, id, type}
  def intent_id({:ensure_dock_host, id, _parent, _opts}), do: {:dock_host, id}
  def intent_id({:ensure_dock_pane, id, _host, _opts}), do: {:dock_pane, id}
  def intent_id({:ensure_gl_canvas, id, _parent, _opts}), do: {:gl_canvas, id}
  def intent_id({:ensure_visual, id, _type, _parent, _opts}), do: {:visual, id}
  def intent_id({:set, id, _props}), do: {:set, id}
  def intent_id({:layout, id, _spec}), do: {:layout, id}

  def intent_id({:tree_add_item, tree_id, item_id, _parent, _opts}), do: {:tree_item, tree_id, item_id}
  def intent_id({:tree_expand, tree_id, item_id}), do: {:tree_expand, tree_id, item_id}
  def intent_id({:tree_collapse, tree_id, item_id}), do: {:tree_collapse, tree_id, item_id}

  def intent_id({:grid_set_cell, grid_id, row, col, _val}), do: {:grid_cell, grid_id, row, col}
  def intent_id({:grid_set_row, grid_id, row, _vals}), do: {:grid_row, grid_id, row}
  def intent_id({:grid_clear, grid_id}), do: {:grid_clear, grid_id}
  def intent_id({:grid_append_row, grid_id, _vals}), do: {:grid_append, grid_id, :erlang.unique_integer()}

  def intent_id({:add_menu, menu_bar_id, menu_id, _opts}), do: {:menu, menu_bar_id, menu_id}
  def intent_id({:add_menu_item, menu_id, item_id, _opts}), do: {:menu_item, menu_id, item_id}
  def intent_id({:add_menu_separator, menu_id}), do: {:menu_sep, menu_id, :erlang.unique_integer()}
  def intent_id({:add_tool, toolbar_id, tool_id, _opts}), do: {:tool, toolbar_id, tool_id}
  def intent_id({:add_tool_separator, toolbar_id}), do: {:tool_sep, toolbar_id, :erlang.unique_integer()}

  def intent_id({:split_vertical, id, _left, _right, _opts}), do: {:split_v, id}
  def intent_id({:split_horizontal, id, _top, _bottom, _opts}), do: {:split_h, id}

  def intent_id({:scroll_set_virtual_size, id, _w, _h}), do: {:scroll_size, id}
  def intent_id({:scroll_to, id, _x, _y}), do: {:scroll_pos, id}

  def intent_id({:html_set_page, id, _html}), do: {:html_page, id}
  def intent_id({:html_load_page, id, _url}), do: {:html_load, id}

  def intent_id(intent), do: {:unknown, :erlang.phash2(intent)}

  ## ------------------------------------------------------------------
  ## Diffable classification
  ## ------------------------------------------------------------------

  @spec diffable?(intent()) :: boolean()
  def diffable?({:refresh, _}), do: false
  def diffable?({:show_dialog, _, _, _, _}), do: false
  def diffable?({:grid_append_row, _, _}), do: false
  def diffable?({:add_menu_separator, _}), do: false
  def diffable?({:add_tool_separator, _}), do: false
  def diffable?({:layout, _, _}), do: false

  # Commands, not declarations: send them with `Cedar.Renderer.render/1` when
  # something happens. Like every other non-diffable intent they are re-applied
  # on every render if a scene returns them from `view/1` — harmless for
  # showing a pane, and for `:load_dock_layout` a loop that puts the panes back
  # where they were saved a few times a second, undoing every drag the user
  # makes. Restoring a layout is an event, not a fact about the model.
  def diffable?({:load_dock_layout, _, _}), do: false
  def diffable?({:update_dock_pane, _, _}), do: false
  def diffable?(_), do: true

  ## ------------------------------------------------------------------
  ## Destroy intents
  ## ------------------------------------------------------------------

  @spec build_destroy_intents(MapSet.t(intent_id()), %{intent_id() => intent()}) :: [intent()]
  defp build_destroy_intents(removed_ids, old_index) do
    removed_ids
    |> Enum.map(fn id -> {id, Map.fetch!(old_index, id)} end)
    |> Enum.filter(fn {_id, intent} -> destroyable?(intent) end)
    |> Enum.sort_by(fn {id, _intent} -> destroy_order(id) end)
    |> Enum.map(fn {_id, intent} -> to_destroy_intent(intent) end)
  end

  defp destroyable?({:ensure_widget, _, _, _, _}), do: true
  defp destroyable?({:ensure_panel, _, _, _}), do: true
  defp destroyable?({:ensure_window, _, _}), do: true
  defp destroyable?({:ensure_dock_pane, _, _, _}), do: true
  defp destroyable?({:ensure_dock_host, _, _, _}), do: true
  defp destroyable?({:ensure_gl_canvas, _, _, _}), do: true
  defp destroyable?({:ensure_visual, _, _, _, _}), do: true
  defp destroyable?(_), do: false

  defp to_destroy_intent({:ensure_widget, id, type, _, _}), do: {:destroy_widget, id, type}
  defp to_destroy_intent({:ensure_panel, id, _, _}), do: {:destroy_panel, id}
  defp to_destroy_intent({:ensure_window, id, _}), do: {:destroy_window, id}
  defp to_destroy_intent({:ensure_dock_pane, id, _, _}), do: {:destroy_dock_pane, id}
  defp to_destroy_intent({:ensure_dock_host, id, _, _}), do: {:destroy_dock_host, id}
  defp to_destroy_intent({:ensure_gl_canvas, id, _, _}), do: {:destroy_gl_canvas, id}
  defp to_destroy_intent({:ensure_visual, id, _, _, _}), do: {:destroy_visual, id}

  defp destroy_order({:widget, _, _}), do: 0
  defp destroy_order({:gl_canvas, _}), do: 0
  defp destroy_order({:visual, _}), do: 0
  defp destroy_order({:panel, _}), do: 1
  defp destroy_order({:dock_pane, _}), do: 1
  # After its panes and before its window. A wxAuiManager must be uninitialised
  # while the window it manages still exists — the other order is an assertion
  # failure inside wxWidgets with no Elixir stack trace to explain it.
  defp destroy_order({:dock_host, _}), do: 2
  defp destroy_order({:window, _}), do: 3
  defp destroy_order(_), do: 0

  ## ------------------------------------------------------------------
  ## Create intents (preserves topological order)
  ## ------------------------------------------------------------------

  @spec build_create_intents(MapSet.t(intent_id()), [intent()]) :: [intent()]
  defp build_create_intents(added_ids, new_intents) do
    Enum.filter(new_intents, fn intent ->
      diffable?(intent) and
        creatable?(intent) and
        MapSet.member?(added_ids, intent_id(intent))
    end)
  end

  defp creatable?({:ensure_window, _, _}), do: true
  defp creatable?({:ensure_panel, _, _, _}), do: true
  defp creatable?({:ensure_widget, _, _, _, _}), do: true
  defp creatable?({:ensure_dock_host, _, _, _}), do: true
  defp creatable?({:ensure_dock_pane, _, _, _}), do: true
  defp creatable?({:ensure_gl_canvas, _, _, _}), do: true
  defp creatable?({:ensure_visual, _, _, _, _}), do: true
  defp creatable?(_), do: false

  ## ------------------------------------------------------------------
  ## Update intents
  ## ------------------------------------------------------------------

  @spec build_update_intents(
          MapSet.t(intent_id()),
          %{intent_id() => intent()},
          %{intent_id() => intent()}
        ) :: [intent()]
  defp build_update_intents(common_ids, old_index, new_index) do
    common_ids
    |> Enum.map(fn id ->
      old_intent = Map.fetch!(old_index, id)
      new_intent = Map.fetch!(new_index, id)
      {id, old_intent, new_intent}
    end)
    |> Enum.flat_map(&diff_intent/1)
  end

  @spec diff_intent({intent_id(), intent(), intent()}) :: [intent()]

  defp diff_intent({_id, {:ensure_window, id, old_opts}, {:ensure_window, id, new_opts}}) do
    if opts_equal?(old_opts, new_opts), do: [], else: [{:update_window, id, new_opts}]
  end

  defp diff_intent({_id, {:ensure_panel, id, parent, old_opts}, {:ensure_panel, id, parent, new_opts}}) do
    if opts_equal?(old_opts, new_opts), do: [], else: [{:update_panel, id, new_opts}]
  end

  defp diff_intent({_id, {:ensure_widget, id, type, parent, old_opts}, {:ensure_widget, id, type, parent, new_opts}}) do
    if opts_equal?(old_opts, new_opts), do: [], else: [{:update_widget, id, type, new_opts}]
  end

  # A visual's declaration is a pure function of the model, so a change here is
  # the normal path rather than an exception: a new colour domain or colormap
  # becomes a minimal GPU update rather than a teardown. The visual itself
  # decides whether it can absorb the change or wants rebuilding.
  defp diff_intent({_id, {:ensure_visual, id, type, parent, old_opts},
                    {:ensure_visual, id, type, parent, new_opts}}) do
    if opts_equal?(old_opts, new_opts), do: [], else: [{:update_visual, id, type, new_opts}]
  end

  # A GL canvas cannot be updated in place — it is created or destroyed — so a
  # change to its options produces no intent at all. Both option lists are named
  # with underscores because they are genuinely ignored, which is worth seeing
  # rather than hiding: a canvas whose size or attributes changed will keep the
  # ones it was built with until something destroys it.
  defp diff_intent({_id, {:ensure_gl_canvas, id, parent, _old_opts},
                    {:ensure_gl_canvas, id, parent, _new_opts}}) do
    []
  end

  # Deliberately nothing. `dock:`, `best_size:` and the rest are where a pane
  # goes the first time it is created; by the time a scene renders again the
  # arrangement belongs to whoever is using the program, and a scene whose
  # options happened to change must not yank a pane back out of the group the
  # user dropped it into. Caption and visibility change through
  # `{:update_dock_pane, id, opts}`, which says so out loud.
  defp diff_intent({_id, {:ensure_dock_pane, id, host, _old}, {:ensure_dock_pane, id, host, _new}}) do
    []
  end

  defp diff_intent({_id, {:ensure_dock_host, id, parent, _old}, {:ensure_dock_host, id, parent, _new}}) do
    []
  end

  defp diff_intent({_id, {:set, id, old_props}, {:set, id, new_props}}) do
    changed_props = diff_props(old_props, new_props)
    if changed_props == [], do: [], else: [{:set, id, changed_props}]
  end

  defp diff_intent({_id, {:layout, id, old_spec}, {:layout, id, new_spec}}) do
    if old_spec == new_spec, do: [], else: [{:layout, id, new_spec}]
  end

  defp diff_intent({_id, old_intent, new_intent}) do
    if old_intent == new_intent, do: [], else: [new_intent]
  end

  ## ------------------------------------------------------------------
  ## Property diffing
  ## ------------------------------------------------------------------

  @spec diff_props(keyword(), keyword()) :: keyword()
  defp diff_props(old_props, new_props) do
    Enum.filter(new_props, fn {key, new_val} ->
      old_val = Keyword.get(old_props, key)
      old_val != new_val
    end)
  end

  @spec opts_equal?(keyword(), keyword()) :: boolean()
  defp opts_equal?(old_opts, new_opts) do
    Enum.sort(old_opts) == Enum.sort(new_opts)
  end

  ## ------------------------------------------------------------------
  ## Action intents (always execute)
  ## ------------------------------------------------------------------

  @spec extract_action_intents([intent()]) :: [intent()]
  defp extract_action_intents(intents) do
    Enum.filter(intents, &(not diffable?(&1)))
  end
end
