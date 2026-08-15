defmodule Cedar.Renderer.Intents do
  @moduledoc """
  Routes intents to specific handler modules.
  """

  alias Cedar.Renderer.Intents.{Window, Panel, Widgets, Layout, Properties, GLCanvas, Visual, Dock}

  # Window operations
  def apply({:ensure_window, _, _} = intent, state), do: Window.apply(intent, state)
  def apply({:update_window, _, _} = intent, state), do: Window.apply(intent, state)
  def apply({:destroy_window, _} = intent, state), do: Window.apply(intent, state)
  def apply({:refresh, _} = intent, state), do: Window.apply(intent, state)

  # Panel operations
  def apply({:ensure_panel, _, _, _} = intent, state), do: Panel.apply(intent, state)
  def apply({:update_panel, _, _} = intent, state), do: Panel.apply(intent, state)
  def apply({:destroy_panel, _} = intent, state), do: Panel.apply(intent, state)

  # Widget operations
  def apply({:ensure_widget, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:update_widget, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:destroy_widget, _, _} = intent, state), do: Widgets.apply(intent, state)

  # Dock operations. A scene declares which panes exist; where they sit is the
  # user's, and comes back out as a perspective rather than as scene state.
  def apply({:ensure_dock_host, _, _, _} = intent, state), do: Dock.apply(intent, state)
  def apply({:destroy_dock_host, _} = intent, state), do: Dock.apply(intent, state)
  def apply({:load_dock_layout, _, _} = intent, state), do: Dock.apply(intent, state)
  def apply({:ensure_dock_pane, _, _, _} = intent, state), do: Dock.apply(intent, state)
  def apply({:update_dock_pane, _, _} = intent, state), do: Dock.apply(intent, state)
  def apply({:destroy_dock_pane, _} = intent, state), do: Dock.apply(intent, state)

  # GL Canvas operations
  def apply({:ensure_gl_canvas, _, _, _} = intent, state), do: GLCanvas.apply(intent, state)
  def apply({:destroy_gl_canvas, _} = intent, state), do: GLCanvas.apply(intent, state)

  # Visual operations
  def apply({:ensure_visual, _, _, _, _} = intent, state), do: Visual.apply(intent, state)
  def apply({:update_visual, _, _, _} = intent, state), do: Visual.apply(intent, state)
  def apply({:destroy_visual, _} = intent, state), do: Visual.apply(intent, state)

  # Dialogs
  def apply({:show_dialog, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)

  # Layout & Properties
  def apply({:layout, _, _} = intent, state), do: Layout.apply(intent, state)
  def apply({:set, _, _} = intent, state), do: Properties.apply(intent, state)

  # Splitter operations
  def apply({:split_vertical, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:split_horizontal, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)

  # Toolbar operations
  def apply({:add_tool, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:add_tool_separator, _} = intent, state), do: Widgets.apply(intent, state)

  # Menu operations
  def apply({:add_menu, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:add_menu_item, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:add_menu_separator, _} = intent, state), do: Widgets.apply(intent, state)

  # Tree operations
  def apply({:tree_add_item, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:tree_expand, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:tree_collapse, _, _} = intent, state), do: Widgets.apply(intent, state)

  # Grid operations
  def apply({:grid_set_cell, _, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:grid_set_row, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:grid_clear, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:grid_append_row, _, _} = intent, state), do: Widgets.apply(intent, state)

  # Scrolled window operations
  def apply({:scroll_set_virtual_size, _, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:scroll_to, _, _, _} = intent, state), do: Widgets.apply(intent, state)

  # HTML window operations
  def apply({:html_set_page, _, _} = intent, state), do: Widgets.apply(intent, state)
  def apply({:html_load_page, _, _} = intent, state), do: Widgets.apply(intent, state)

  def apply(intent, state) do
    require Logger
    Logger.warning("Renderer: unhandled intent #{inspect(intent)}")
    state
  end
end
