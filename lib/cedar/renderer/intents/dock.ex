defmodule Cedar.Renderer.Intents.Dock do
  @moduledoc false
  # Intent handler for dockable panes, backed by wxAuiManager.
  #
  # ## Who owns what
  #
  # A scene declares which panes exist, what they are called and what is inside
  # them. It does NOT own where they are. Position, size, docked-or-floating,
  # tab order and the order of the docks are the user's, and they change with
  # the mouse without the scene being consulted.
  #
  # That split is the whole design. Cedar's contract everywhere else is that a
  # scene declares and the renderer applies, one direction, no argument. A dock
  # manager is the first thing that breaks it, because the user moves the
  # furniture. A Cedar that treated pane geometry as scene state would put a
  # pane back where the model believed it belonged half a second after the
  # operator dragged it somewhere else, forever.
  #
  # So `dock:` is a *default* — where a pane goes the first time it is created,
  # and never again. The arrangement is read back out as a perspective string
  # via `Cedar.Renderer.save_dock_layout/1` and handed back with
  # `{:load_dock_layout, host, blob}`. Save it with the user's preferences;
  # Cedar never inspects it. That is also the feature every application in this
  # genre ships as "reset window layout".
  #
  # ## A pane is a panel
  #
  # `{:ensure_dock_pane, id, host, opts}` creates a `wxPanel` and registers it
  # in `state.panels`, so every widget, layout and visual intent that can
  # target a panel can target a pane with no changes anywhere. A pane is a
  # placement, not a new kind of container.
  #
  # ## Why the host gets its own panel
  #
  # wxAuiManager lays out the client area of the window it manages, and both
  # `:ensure_window` and `:ensure_panel` fit their creations with a sizer.
  # A sizer and a dock manager laying out the same children disagree visibly.
  # So the host creates one bare panel of its own, with no sizer, and manages
  # that — which also means a dock host can sit inside an ordinary layout
  # beside ordinary widgets rather than having to be the whole window.

  use WxEx
  require Logger

  # ── Hosts ─────────────────────────────────────────────────────────────────

  def apply({:ensure_dock_host, host_id, parent_id, opts}, state) do
    if Map.has_key?(state.dock_hosts, host_id) do
      state
    else
      case resolve_parent(parent_id, state) do
        nil ->
          Logger.debug("Renderer: parent not ready for dock host #{inspect(host_id)}")
          state

        parent ->
          # No sizer on this one, deliberately. See the moduledoc.
          host_panel = :wxPanel.new(parent)

          if sizer = Map.get(state.sizers, parent_id) do
            :wxSizer.add(sizer, host_panel, proportion: 1, flag: wxEXPAND())

            # Laid out now rather than at the next refresh. wxAuiManager sizes
            # its panes from the window it manages, so a host that is still
            # zero-by-zero when the first pane is added gives every pane a
            # degenerate size — and AUI remembers those as the pane's own
            # geometry rather than recomputing them when the window later grows.
            :wxSizer.layout(sizer)
          end

          manager = :wxAuiManager.new(managed_wnd: host_panel)

          # Close is the one arrangement change a scene may genuinely need to
          # know about, because a closed pane usually has a menu item that
          # should stop looking ticked. Dragging a pane from one side to the
          # other is not reported, on purpose: nothing in the application is
          # entitled to have an opinion about it.
          :wxAuiManager.connect(manager, :aui_pane_close, skip: true)

          %{
            state
            | dock_hosts:
                Map.put(state.dock_hosts, host_id, %{
                  manager: manager,
                  panel: host_panel,
                  parent: parent_id,
                  panes: [],
                  pending: MapSet.new(),
                  hidden: MapSet.new(),
                  caption_height: Keyword.get(opts, :caption_height)
                })
          }
      end
    end
  end

  def apply({:destroy_dock_host, host_id}, state), do: teardown_host(host_id, state)

  def apply({:load_dock_layout, host_id, blob}, state) when is_binary(blob) do
    with_host(host_id, state, fn host ->
      # An arrangement saved by a different build can name panes that no longer
      # exist. wxAUI drops those quietly, which is the right behaviour and the
      # reason this does not try to validate the string first: the panes that
      # do still exist should come back where the user left them, rather than
      # everything reverting because one is gone.
      :wxAuiManager.loadPerspective(host.manager, blob, update: true)
      state
    end)
  end

  # ── Panes ─────────────────────────────────────────────────────────────────

  def apply({:ensure_dock_pane, pane_id, host_id, opts}, state) do
    cond do
      Map.has_key?(state.dock_panes, pane_id) ->
        state

      not Map.has_key?(state.dock_hosts, host_id) ->
        Logger.debug("Renderer: dock host #{inspect(host_id)} not ready for #{inspect(pane_id)}")
        state

      true ->
        host = Map.fetch!(state.dock_hosts, host_id)

        panel = :wxPanel.new(host.panel)
        sizer = :wxBoxSizer.new(wxVERTICAL())
        :wxPanel.setSizer(panel, sizer)

        if bg = Keyword.get(opts, :background) do
          :wxPanel.setBackgroundColour(panel, bg)
        end

        :wxAuiManager.addPane(host.manager, panel, pane_info(pane_id, opts))
        :wxAuiManager.update(host.manager)

        %{
          state
          | panels: Map.put(state.panels, pane_id, panel),
            sizers: Map.put(state.sizers, pane_id, sizer),
            dock_panes: Map.put(state.dock_panes, pane_id, %{host: host_id, window: panel}),
            dock_hosts:
              Map.update!(state.dock_hosts, host_id, fn host ->
                %{host | panes: host.panes ++ [pane_id], pending: MapSet.put(host.pending, pane_id)}
              end)
        }
    end
  end

  # Show, hide and caption only. Not position: a scene asking for a pane to
  # move is a scene overruling the person using it.
  #
  # A command rather than a declaration — send it with `Cedar.Renderer.render/1`
  # when something happens, the way a dialog is shown.
  def apply({:update_dock_pane, pane_id, opts}, state) do
    with_pane(pane_id, state, fn host, info ->
      if caption = Keyword.get(opts, :caption) do
        :wxAuiPaneInfo.caption(info, caption)
      end

      case Keyword.fetch(opts, :shown) do
        {:ok, true} -> :wxAuiPaneInfo.show(info)
        {:ok, false} -> :wxAuiPaneInfo.hide(info)
        :error -> :ok
      end

      :wxAuiManager.update(host.manager)
      state
    end)
  end

  def apply({:destroy_dock_pane, pane_id}, state) do
    case Map.get(state.dock_panes, pane_id) do
      nil ->
        state

      %{host: host_id, window: panel} ->
        state =
          with_host(host_id, state, fn host ->
            :wxAuiManager.detachPane(host.manager, panel)
            :wxAuiManager.update(host.manager)
            state
          end)

        :wxPanel.destroy(panel)

        %{
          state
          | panels: Map.delete(state.panels, pane_id),
            sizers: Map.delete(state.sizers, pane_id),
            dock_panes: Map.delete(state.dock_panes, pane_id),
            dock_hosts:
              Map.update(state.dock_hosts, host_id, nil, fn host ->
                %{host | panes: host.panes -- [pane_id], hidden: MapSet.delete(host.hidden, pane_id)}
              end)
        }
    end
  end

  @doc false
  # A pane is added before the widgets that go in it — a scene declares the
  # container and then its contents, in that order, because that is the only
  # order that can work. So the dock sizes wxAUI computes at `addPane` are
  # computed from empty panels, and a pane that asked for 200 wide gets
  # whatever an empty panel's best size happens to be. Eighteen pixels, as it
  # turns out.
  #
  # `{:refresh, window}` is the existing "I have finished declaring, lay it
  # out" intent, so that is where the second update belongs. Only when panes
  # were actually added: refresh is re-emitted on every render, and running
  # wxAUI's layout at frame rate would fight the mouse of anyone dragging a
  # pane while it happened.
  def refresh(state) do
    Enum.reduce(state.dock_hosts, state, fn
      {_host_id, %{pending: pending}}, state when map_size(pending) == 0 ->
        state

      {host_id, host}, state ->
        :wxAuiManager.update(host.manager)
        put_in(state.dock_hosts[host_id].pending, MapSet.new())
    end)
  end

  # ── Reading back what the user did ────────────────────────────────────────

  @doc false
  def save_perspective(host_id, state) do
    case Map.get(state.dock_hosts, host_id) do
      nil -> :error
      host -> {:ok, IO.iodata_to_binary(:wxAuiManager.savePerspective(host.manager))}
    end
  end

  @doc false
  # Which panes are on screen, floating, or docked, for a scene that wants to
  # tick a View menu. Asked for rather than pushed: this changes on every drag
  # and an event per drag would be noise.
  def layout(host_id, state) do
    case Map.get(state.dock_hosts, host_id) do
      nil ->
        :error

      host ->
        {:ok,
         Map.new(host.panes, fn pane_id ->
           info = :wxAuiManager.getPane(host.manager, pane_name(pane_id))

           {pane_id,
            %{
              shown: :wxAuiPaneInfo.isShown(info),
              floating: :wxAuiPaneInfo.isFloating(info),
              docked: :wxAuiPaneInfo.isDocked(info)
            }}
         end)}
    end
  end

  @doc false
  # Called after a close event has been through wx. The event carries a
  # `wxAuiPaneInfo` whose window the Erlang binding does not expose a getter
  # for, so the pane cannot be identified from the event itself — and the close
  # has not happened yet when the event arrives anyway. Comparing what is shown
  # now against what was shown before answers both problems at once, and
  # answers them for any route to a hidden pane rather than only for the close
  # button.
  def reconcile(host_id, state) do
    case layout(host_id, state) do
      :error ->
        {[], state}

      {:ok, panes} ->
        host = Map.fetch!(state.dock_hosts, host_id)
        hidden = for {pane_id, %{shown: false}} <- panes, into: MapSet.new(), do: pane_id

        events =
          for pane_id <- MapSet.difference(hidden, host.hidden),
              do: {:dock_pane, pane_id, :closed}

        {events, put_in(state.dock_hosts[host_id].hidden, hidden)}
    end
  end

  @doc false
  # Every manager, so a window going away does not leave one pointing at
  # destroyed C++ objects. wxAuiManager must be uninitialised before the window
  # it manages is destroyed; the other order is an assertion failure inside
  # wxWidgets, at exit, with no Elixir stack trace to explain it.
  def teardown_for_window(window_id, state) do
    state.dock_hosts
    |> Enum.filter(fn {_id, host} -> host.parent == window_id end)
    |> Enum.reduce(state, fn {host_id, _host}, state -> teardown_host(host_id, state) end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp teardown_host(host_id, state) do
    case Map.get(state.dock_hosts, host_id) do
      nil ->
        state

      host ->
        :wxAuiManager.unInit(host.manager)
        :wxAuiManager.destroy(host.manager)

        state = Enum.reduce(host.panes, state, &forget_pane/2)
        %{state | dock_hosts: Map.delete(state.dock_hosts, host_id)}
    end
  end

  # The panels went with the managed window; only the bookkeeping is left.
  defp forget_pane(pane_id, state) do
    %{
      state
      | panels: Map.delete(state.panels, pane_id),
        sizers: Map.delete(state.sizers, pane_id),
        dock_panes: Map.delete(state.dock_panes, pane_id)
    }
  end

  defp with_host(host_id, state, fun) do
    case Map.get(state.dock_hosts, host_id) do
      nil ->
        Logger.debug("Renderer: no dock host #{inspect(host_id)}")
        state

      host ->
        fun.(host)
    end
  end

  defp with_pane(pane_id, state, fun) do
    case Map.get(state.dock_panes, pane_id) do
      nil ->
        Logger.debug("Renderer: no dock pane #{inspect(pane_id)}")
        state

      %{host: host_id} ->
        with_host(host_id, state, fn host ->
          fun.(host, :wxAuiManager.getPane(host.manager, pane_name(pane_id)))
        end)
    end
  end

  # The name wxAUI writes into the perspective string, so it has to be stable
  # across runs and unique within a host. `inspect/1` of an atom or a tagged
  # tuple is both.
  defp pane_name(pane_id), do: inspect(pane_id)

  defp pane_info(pane_id, opts) do
    dock = Keyword.get(opts, :dock, :left)

    # The centre pane is not a direction and cannot be one: it is what the docks
    # surround, there is exactly one, and it never floats, closes or wears a
    # caption. Making it a value of the same option is what stops a caller
    # asking for two of them — and it is why the defaults below are read off
    # it rather than being constants a viewport would have to override one by
    # one and would eventually get wrong.
    centre? = dock == :centre

    info = :wxAuiPaneInfo.new()

    :wxAuiPaneInfo.name(info, pane_name(pane_id))
    :wxAuiPaneInfo.caption(info, Keyword.get(opts, :caption, ""))
    place(info, dock)

    # `size:` is the extent the pane docks at, and it is set as both the best
    # size and the minimum because the minimum is what wxAUI actually reads.
    #
    # Measured rather than assumed, twice. A pane given only a best size of 200
    # docks at eighteen pixels — the best size of the empty panel it was
    # created from, because a scene declares a container before the widgets
    # that go in it and no other order could work. A pane given both docks at
    # its *minimum*, whatever its best size says. So there is one knob here
    # rather than the two wxWidgets documents, because only one of them does
    # anything, and offering a `min_size:` that silently overrode `size:` would
    # be shipping that confusion rather than absorbing it.
    if size = Keyword.get(opts, :size) do
      :wxAuiPaneInfo.bestSize(info, size)
      :wxAuiPaneInfo.minSize(info, size)
    end

    # These take a keyword list, not a bare boolean, and the key is not the same
    # one for all of them: wx generates the option name from the C++ parameter,
    # so it is `b` where wxWidgets wrote `bool b` and `visible` where it wrote
    # `bool visible`. Getting it wrong is a FunctionClauseError inside wx.
    :wxAuiPaneInfo.floatable(info, b: Keyword.get(opts, :floatable, not centre?))
    :wxAuiPaneInfo.dockable(info, b: Keyword.get(opts, :dockable, not centre?))
    :wxAuiPaneInfo.closeButton(info, visible: Keyword.get(opts, :closable, not centre?))
    :wxAuiPaneInfo.captionVisible(info, visible: Keyword.get(opts, :caption_visible, not centre?))
    :wxAuiPaneInfo.gripper(info, visible: Keyword.get(opts, :gripper, false))
    :wxAuiPaneInfo.paneBorder(info, visible: Keyword.get(opts, :border, true))

    if Keyword.get(opts, :floating, false), do: :wxAuiPaneInfo.float(info)
    if not Keyword.get(opts, :shown, true), do: :wxAuiPaneInfo.hide(info)

    info
  end

  defp place(info, :centre), do: :wxAuiPaneInfo.centrePane(info)
  defp place(info, :left), do: :wxAuiPaneInfo.left(info)
  defp place(info, :right), do: :wxAuiPaneInfo.right(info)
  defp place(info, :top), do: :wxAuiPaneInfo.top(info)
  defp place(info, :bottom), do: :wxAuiPaneInfo.bottom(info)

  defp place(_info, other) do
    raise ArgumentError,
          "unknown dock #{inspect(other)}; known: :left, :right, :top, :bottom, :centre"
  end

  defp resolve_parent(parent_id, state) do
    Map.get(state.windows, parent_id) || Map.get(state.panels, parent_id)
  end
end
