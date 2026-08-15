# Dockable panes, the way a CAD suite arranges itself.
#
#     mix run examples/docking.exs
#
# Drag a pane's caption bar out of the window and it floats. Drag it back
# against an edge and it docks there. Drop it onto another pane and they become
# a tabbed group. Close one with its × and it goes away. None of that is code
# in this file, and none of it is state in the model.
#
# That is the point worth demonstrating. A scene declares which panes exist,
# what they are called and what is inside them. Where they are is the user's,
# and Cedar does not model it — it is read back out as an opaque perspective
# string and handed back later. "Save layout" and "Restore layout" below are
# the whole of that API.
#
# The spinning cube in the centre is a real OpenGL surface, and it is there to
# prove the thing most likely to break: the centre pane is the one pane that
# cannot float, so the GL context is never reparented into a new top-level
# window, and the viewport keeps drawing while everything around it is dragged
# about.

Logger.configure(level: :info)

defmodule DockingDemo do
  @moduledoc false

  use Cedar.Scene

  alias Cedar.Math
  alias Cedar.Renderer

  @panes [
    pendant: "Pendant",
    tree: "Model tree",
    output: "Output"
  ]

  def init(_args) do
    %{
      angle: 0.0,
      saved: nil,
      held: false,
      # Every press and release, in order, so that "did the events arrive" is a
      # question with an answer rather than an impression.
      log: [],
      status: "press and hold the button at the bottom of this pane"
    }
  end

  # ── events ────────────────────────────────────────────────────────────────

  def handle_event({:ui_event, :save, :click}, model) do
    case Renderer.save_dock_layout(:dock) do
      {:ok, blob} ->
        %{model | saved: blob, status: "layout saved (#{byte_size(blob)} bytes)"}

      :error ->
        %{model | status: "no dock host to save"}
    end
  end

  def handle_event({:ui_event, :restore, :click}, %{saved: nil} = model) do
    %{model | status: "nothing saved yet"}
  end

  def handle_event({:ui_event, :restore, :click}, model) do
    # A one-shot, so it is rendered directly rather than returned from view/1:
    # view/1 runs after every change, and an intent that reloads the layout
    # would undo the user's next drag on the next frame.
    Renderer.render({:load_dock_layout, :dock, model.saved})
    %{model | status: "layout restored"}
  end

  def handle_event({:ui_event, :show_all, :click}, model) do
    for {pane, _caption} <- @panes do
      Renderer.render({:update_dock_pane, pane, shown: true})
    end

    %{model | status: "all panes shown"}
  end

  def handle_event({:ui_event, :where, :click}, model) do
    case Renderer.dock_layout(:dock) do
      {:ok, panes} ->
        %{model | status: Enum.map_join(panes, "   ", &describe/1)}

      :error ->
        %{model | status: "no dock host"}
    end
  end

  # A held button reports going down and coming up rather than being clicked,
  # which is what a jog needs: the machine moves for as long as the operator is
  # holding the control, and stops when they let go — including when they let
  # go by dragging off the button, or by the window losing the mouse entirely.
  def handle_event({:ui_event, :hold_me, :press}, model) do
    %{model | held: true, log: log(model, :press), status: "HELD — an axis would be moving now"}
  end

  def handle_event({:ui_event, :hold_me, :release}, %{held: true} = model) do
    %{
      model
      | held: false,
        log: log(model, :release),
        status: "released after #{length(model.log)} event(s) — an axis would have stopped"
    }
  end

  # A release with nothing held: the pointer crossing the button on its way
  # somewhere else. Recorded, because it is the difference between "leaving
  # stops a jog" and "leaving fires constantly".
  def handle_event({:ui_event, :hold_me, :release}, model) do
    %{model | log: log(model, :idle_release)}
  end


  # Closing a pane is the one arrangement change the scene hears about, because
  # a closed pane usually has a menu item that should stop looking ticked.
  def handle_event({:dock_pane, pane_id, :closed}, model) do
    %{model | status: "#{pane_id} closed — Show all brings it back"}
  end

  def handle_event(_event, model), do: model

  defp log(model, what), do: model.log ++ [{what, System.system_time(:millisecond)}]

  # Degrees: Cedar.Math.rotation_y/1 takes them, and a matrix built from a
  # radian's worth of degrees is a cube that appears not to be turning.
  def handle_info(:tick, model), do: {:noreply, %{model | angle: model.angle + 3.0}}
  def handle_info(_msg, model), do: {:noreply, model}

  # ── view ──────────────────────────────────────────────────────────────────

  def view(model) do
    [
      {:ensure_window, :main, title: "cedar — docking", size: {1100, 720}},
      {:ensure_panel, :root, :main, []},
      {:ensure_dock_host, :dock, :root, []},

      # The centre pane: what the docks surround. One per host, never floating,
      # no caption, no close button — it is the document, not a tool.
      {:ensure_dock_pane, :viewport, :dock, dock: :centre},
      {:ensure_visual, :cube, :mesh, :viewport,
       size: {640, 480},
       fps: 30,
       notify: self(),
       clear: {0.10, 0.11, 0.13, 1.0},
       mesh: cube(),
       model: Math.multiply(Math.rotation_y(model.angle), Math.rotation_x(28.0)),
       eye: {0.0, 0.0, 4.0},
       target: {0.0, 0.0, 0.0},
       light_direction: {-0.35, 0.75, 0.55},
       base_color: {0.85, 0.78, 0.35, 1.0}},

      # Tools. `dock:` is where each one goes the first time and never again;
      # after that the arrangement belongs to whoever is using the program.
      {:ensure_dock_pane, :pendant, :dock,
       caption: "Pendant", dock: :right, size: {260, 500}},
      {:ensure_widget, :save, :button, :pendant, label: "Save layout"},
      {:ensure_widget, :restore, :button, :pendant, label: "Restore layout"},
      {:ensure_widget, :show_all, :button, :pendant, label: "Show all panes"},
      {:ensure_widget, :where, :button, :pendant, label: "Where is everything?"},
      {:ensure_widget, :hold_me, :button, :pendant, label: "Hold me", hold: true},
      # Loud on purpose. If the label does not change while the button is down,
      # macOS ate the event and no amount of squinting at the machine will say
      # otherwise.
      {:set, :hold_me, label: if(model.held, do: "▼ HOLDING ▼", else: "Hold me")},
      {:layout, :pendant, {:vbox, [], [:save, :restore, :show_all, :where, :hold_me]}},

      {:ensure_dock_pane, :tree, :dock,
       caption: "Model tree", dock: :left, size: {220, 500}},
      {:ensure_widget, :tree_label, :static_text, :tree,
       label: "  (a tree would go here)"},
      {:layout, :tree, {:vbox, [], [:tree_label]}},

      {:ensure_dock_pane, :output, :dock,
       caption: "Output", dock: :bottom, size: {900, 110}},
      {:ensure_widget, :status, :static_text, :output, label: model.status},
      {:set, :status, label: model.status},
      {:layout, :output, {:vbox, [], [:status]}},
      {:refresh, :main}
    ]
  end

  defp describe({pane, %{shown: false}}), do: "#{pane}: closed"
  defp describe({pane, %{floating: true}}), do: "#{pane}: floating"
  defp describe({pane, _}), do: "#{pane}: docked"

  # ── a cube ────────────────────────────────────────────────────────────────

  # Eight corners shared between faces would give one normal per corner and a
  # cube shaded like a sphere. Twenty-four vertices, four per face, is what
  # makes the edges edges.
  defp cube do
    faces = [
      {{0, 0, 1}, [{-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1}]},
      {{0, 0, -1}, [{1, -1, -1}, {-1, -1, -1}, {-1, 1, -1}, {1, 1, -1}]},
      {{1, 0, 0}, [{1, -1, 1}, {1, -1, -1}, {1, 1, -1}, {1, 1, 1}]},
      {{-1, 0, 0}, [{-1, -1, -1}, {-1, -1, 1}, {-1, 1, 1}, {-1, 1, -1}]},
      {{0, 1, 0}, [{-1, 1, 1}, {1, 1, 1}, {1, 1, -1}, {-1, 1, -1}]},
      {{0, -1, 0}, [{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, {-1, -1, 1}]}
    ]

    positions =
      for {_normal, corners} <- faces,
          {x, y, z} <- corners,
          do: {x * 1.0, y * 1.0, z * 1.0}

    indices =
      for face <- 0..5 do
        base = face * 4
        [{base, base + 1, base + 2}, {base, base + 2, base + 3}]
      end
      |> List.flatten()

    %{positions: positions, indices: indices}
  end
end

{:ok, scene} = Cedar.start_scene(DockingDemo)

# The cube turns on a clock outside the scene, because a scene is a pure
# function of its model and has none of its own.
spawn_link(fn ->
  Stream.interval(60) |> Enum.each(fn _ -> send(scene, :tick) end)
end)

# `mix run` would exit immediately otherwise, taking the window with it.
if not IEx.started?() do
  Process.sleep(:infinity)
end
