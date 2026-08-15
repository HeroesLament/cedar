defmodule Cedar.Renderer.Intents.Layout do
  use WxEx
  require Logger

  def apply({:layout, parent_id, layout_spec}, state) do
    Logger.debug("Layout: applying layout to #{inspect(parent_id)}")
    parent = Map.get(state.panels, parent_id)
    sizer = Map.get(state.sizers, parent_id)

    if is_nil(sizer) do
      Logger.debug("Renderer: layout sizer not ready for #{inspect(parent_id)}")
      state
    else
      :wxSizer.clear(sizer, delete_windows: false)

      case layout_spec do
        {:vbox, opts, children} ->
          apply_box_layout(:vertical, sizer, children, state, opts)

        {:hbox, opts, children} ->
          apply_box_layout(:horizontal, sizer, children, state, opts)
      end

      if parent do
        :wxWindow.layout(parent)
      end

      state
    end
  end

  defp apply_box_layout(orientation, sizer, children, state, opts) do
    box =
      case orientation do
        :vertical -> :wxBoxSizer.new(wxVERTICAL())
        :horizontal -> :wxBoxSizer.new(wxHORIZONTAL())
      end

    Enum.each(children, fn child_spec ->
      add_child_to_sizer(box, child_spec, state)
    end)

    proportion = Keyword.get(opts, :proportion, 1)
    :wxSizer.add(sizer, box, proportion: proportion, flag: wxEXPAND())
  end

  # Handle nested hbox/vbox
  defp add_child_to_sizer(sizer, {:hbox, opts, children}, state) do
    nested = :wxBoxSizer.new(wxHORIZONTAL())
    Enum.each(children, fn child -> add_child_to_sizer(nested, child, state) end)
    proportion = Keyword.get(opts, :proportion, 0)
    :wxSizer.add(sizer, nested, proportion: proportion, flag: wxEXPAND())
  end

  defp add_child_to_sizer(sizer, {:vbox, opts, children}, state) do
    nested = :wxBoxSizer.new(wxVERTICAL())
    Enum.each(children, fn child -> add_child_to_sizer(nested, child, state) end)
    proportion = Keyword.get(opts, :proportion, 0)
    :wxSizer.add(sizer, nested, proportion: proportion, flag: wxEXPAND())
  end

  # Handle spacer
  defp add_child_to_sizer(sizer, {:spacer, size}, _state) do
    :wxSizer.addSpacer(sizer, size)
  end

  # Handle widget/panel reference
  defp add_child_to_sizer(sizer, child_spec, state) do
    {child_id, child_opts} = normalize_child(child_spec)

    child = find_child(child_id, state)

    if child do
      proportion = Keyword.get(child_opts, :proportion, 0)
      flag = child_flag(child_opts)
      :wxSizer.add(sizer, child, proportion: proportion, flag: flag)
    else
      Logger.debug("Renderer: layout child not found #{inspect(child_id)}")
    end
  end

  defp normalize_child({id, opts}) when is_list(opts), do: {id, opts}
  defp normalize_child(id), do: {id, []}

  # Look up child widget/panel, including GL canvases
  defp find_child(child_id, state) do
    dock_host(state, child_id) ||
      Map.get(state.panels, child_id) ||
      Map.get(state.widgets, child_id) ||
      # Notebooks live in their own map, and leaving them out here meant a
      # notebook could never appear in a layout spec: it added itself to the
      # parent sizer when created, then the first :layout cleared that sizer
      # and could not find it to put back.
      Map.get(state.notebooks, child_id) ||
      Map.get(state.widgets, {:gl_canvas, child_id})
  end

  defp child_flag(opts) do
    case Keyword.get(opts, :align, :expand) do
      :center -> wxALIGN_CENTER_HORIZONTAL()
      :left -> wxALIGN_LEFT()
      :right -> wxALIGN_RIGHT()
      :expand -> wxEXPAND()
      _ -> wxEXPAND()
    end
  end
  # A dock host is placed in a layout like any other child: it is a region of
  # the window that happens to be arranged by a dock manager rather than by a
  # sizer. Resolved from its own table rather than from `panels`, so that it
  # cannot also be found as a *parent* for a widget — it has no sizer, on
  # purpose, and a widget added to it would be laid out by nothing.
  defp dock_host(state, child_id) do
    case Map.get(state.dock_hosts, child_id) do
      %{panel: panel} -> panel
      nil -> nil
    end
  end
end
