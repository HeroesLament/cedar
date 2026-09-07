defmodule Cedar.Intent do
  @moduledoc """
  Typespecs for render intents.

  Intents are declarative instructions that scenes emit
  and the Renderer applies to the wx environment.
  """

  @type widget_id :: atom() | {atom(), term()}
  @type host_id :: atom()
  @type pane_id :: atom() | {atom(), term()}
  @type parent_id :: atom() | {atom(), term()}
  @type window_id :: atom()

  @type opts :: keyword()

  @type widget_type ::
          :static_text
          | :choice
          | :notebook
          | :button
          | :checkbox
          | :text_ctrl
          | :combo_box
          | :colour_field
          | :pick_field

  @type layout_spec ::
          {:vbox, opts(), [widget_id()]}
          | {:hbox, opts(), [widget_id()]}

  @typedoc """
  Where a pane goes the FIRST time it is created, and never again.

  `:centre` is what the docks surround: one per host, never floating, never
  closable, no caption. Everything else is a side.
  """
  @type dock :: :left | :right | :top | :bottom | :centre

  @type t ::
          {:ensure_window, window_id(), opts()}
          | {:ensure_dock_host, host_id(), parent_id(), opts()}
          | {:ensure_dock_pane, pane_id(), host_id(), opts()}
          | {:update_dock_pane, pane_id(), opts()}
          | {:destroy_dock_pane, pane_id()}
          | {:destroy_dock_host, host_id()}
          | {:load_dock_layout, host_id(), binary()}
          | {:ensure_panel, widget_id(), parent_id(), opts()}
          | {:ensure_widget, widget_id(), widget_type(), parent_id(), opts()}
          | {:set, widget_id(), props :: keyword()}
          | {:layout, parent_id(), layout_spec()}

  @type intents :: [t()]
end
