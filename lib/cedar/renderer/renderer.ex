defmodule Cedar.Renderer do
  @moduledoc """
  Owns the wx environment and applies declarative render intents.

  This is the ONLY module allowed to call wx APIs.
  """

  use GenServer
  use WxEx

  require Logger

  alias Cedar.Event
  alias Cedar.Renderer.ComponentRegistry
  alias Cedar.Renderer.Intents
  alias Cedar.Renderer.Intents.Dock

  ## ------------------------------------------------------------------
  ## Public API
  ## ------------------------------------------------------------------

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def render(intent) do
    GenServer.cast(__MODULE__, {:render, intent})
  end

  @doc """
  The arrangement of a dock host, as an opaque string.

  Save it with the user's preferences and hand it back with
  `{:load_dock_layout, host, blob}`. Cedar does not inspect it and neither
  should anything else — it is wxAUI's own format and it will change when
  wxWidgets changes it.

  A question rather than an intent, because it has an answer. Restoring is a
  command and stays an intent.
  """
  @spec save_dock_layout(atom()) :: {:ok, binary()} | :error
  def save_dock_layout(host_id) do
    GenServer.call(__MODULE__, {:save_dock_layout, host_id})
  end

  @doc """
  Which panes of a host are shown, floating or docked.

  Asked for rather than pushed. This changes on every drag, and a scene that
  received an event for each would be listening to the user rearrange their
  furniture — which is not a thing an application is entitled to have an
  opinion about. Ask when you have a reason to care, such as ticking a View
  menu as it opens.
  """
  @spec dock_layout(atom()) :: {:ok, %{term() => map()}} | :error
  def dock_layout(host_id) do
    GenServer.call(__MODULE__, {:dock_layout, host_id})
  end

  def set_theme(theme_module) do
    GenServer.call(__MODULE__, {:set_theme, theme_module})
  end

  def get_theme do
    GenServer.call(__MODULE__, :get_theme)
  end

  ## ------------------------------------------------------------------
  ## Lifecycle
  ## ------------------------------------------------------------------

  @impl true
  def init(:ok) do
    wx = new_wx!()

    # Initialize OpenGL NIF - required on macOS 26+ where on_load doesn't work automatically
    init_opengl_nif()

    mode = detect_mode()

    {:ok,
     %{
       wx: wx,
       windows: %{},
       panels: %{},
       widgets: %{},
       notebooks: %{},
       dock_hosts: %{},
       dock_panes: %{},
       sizers: %{},
       widget_ids: %{},
       theme: Cedar.Theme,
       mode: mode
     }}
  end

  ## ------------------------------------------------------------------
  ## GenServer callbacks
  ## ------------------------------------------------------------------

  @impl true
  def handle_cast({:render, intent}, state) do
    Logger.debug("Renderer intent: #{inspect(intent)}")
    {:noreply, Intents.apply(intent, state)}
  end

  @impl true
  def handle_call({:save_dock_layout, host_id}, _from, state) do
    {:reply, Dock.save_perspective(host_id, state), state}
  end

  def handle_call({:dock_layout, host_id}, _from, state) do
    {:reply, Dock.layout(host_id, state), state}
  end

  def handle_call({:set_theme, theme_module}, _from, state) do
    {:reply, :ok, %{state | theme: theme_module}}
  end

  @impl true
  def handle_call(:get_theme, _from, state) do
    {:reply, {state.theme, state.mode}, state}
  end

  # Dock manager events, ahead of the generic wx clauses because they carry no
  # widget id to look up: wxAUI reports the pane as a `wxAuiPaneInfo`, and the
  # Erlang binding exposes no getter for the window inside it.
  #
  # Nothing has happened yet either — a close event arrives before wx hides
  # anything — so this schedules a reconcile rather than acting. Comparing what
  # is shown now against what was shown before identifies the pane without
  # needing the event to say, and catches every other route to a hidden pane
  # for free.
  @impl true
  def handle_info({:wx, _, _obj, _user_data, event}, state)
      when is_tuple(event) and elem(event, 0) == :wxAuiManager do
    Enum.each(Map.keys(state.dock_hosts), &send(self(), {:dock_reconcile, &1}))
    {:noreply, state}
  end

  def handle_info({:wx, _, source, event}, state) do
    Logger.debug("Renderer wx event: source=#{inspect(source)} event=#{inspect(event)}")
    handle_wx_event(source, event, state)
  end

  def handle_info({:wx, _, source, _user_data, event}, state) do
    Logger.debug(
      "Renderer wx event (with user_data): source=#{inspect(source)} event=#{inspect(event)}"
    )

    handle_wx_event(source, event, state)
  end

  def handle_info({:dock_reconcile, host_id}, state) do
    {events, state} = Dock.reconcile(host_id, state)
    Enum.each(events, &Cedar.Coordinator.broadcast_event/1)
    {:noreply, state}
  end

  def handle_info({:dialog_result, _dialog_id, _result} = event, state) do
    Cedar.Coordinator.broadcast_event(event)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Renderer unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp handle_wx_event(source, event, state) do
    case Map.get(state.widget_ids, source) do
      nil ->
        Logger.debug("Renderer: no widget_id for source #{inspect(source)}")
        {:noreply, state}

      {:gl_canvas, _canvas_id} = widget_id ->
        # GL canvas events - route to canvas server
        handle_gl_canvas_event(widget_id, source, event, state)

      widget_id ->
        # Regular widget events
        handle_regular_widget_event(widget_id, source, event, state)
    end
  end

  defp handle_regular_widget_event(widget_id, source, event, state) do
    ui_event = Event.from_wx(widget_id, {:wx, nil, source, event})
    Logger.debug("Renderer: translated to #{inspect(ui_event)}")

    case ComponentRegistry.lookup(widget_id) do
      nil ->
        Logger.debug("Renderer: no component registered for #{inspect(widget_id)}")

      pid ->
        Logger.debug("Renderer: sending to #{inspect(pid)}")
        send(pid, ui_event)
    end

    {:noreply, state}
  end

  defp handle_gl_canvas_event(widget_id, source, event, state) do
    case ComponentRegistry.lookup(widget_id) do
      nil ->
        Logger.debug("Renderer: no GL canvas server for #{inspect(widget_id)}")
        {:noreply, state}

      pid ->
        gl_event = translate_gl_canvas_event(source, event)

        if gl_event do
          Logger.debug("Renderer: sending GL event to #{inspect(pid)}: #{inspect(gl_event)}")
          send(pid, gl_event)
        end

        {:noreply, state}
    end
  end

  # Resize event
  defp translate_gl_canvas_event(source, {:wxSize, :size, size, _rect}) do
    logical_size = size
    dpi_scale = get_dpi_scale(source)
    {lw, lh} = logical_size
    pixel_size = {trunc(lw * dpi_scale), trunc(lh * dpi_scale)}

    {:wx_resize, logical_size, pixel_size, dpi_scale}
  end

  # Mouse events, positionally rather than by shape.
  #
  # The `wxMouse` record has grown: this wx build sends fourteen elements
  # (three trailing wheel fields) where the twelve-element form was written
  # against. Matching the whole tuple therefore silently stopped matching, and
  # since nothing in the library used canvas input until now, every click has
  # been quietly falling through to "unhandled" - the widgets kept working, so
  # there was nothing to notice.
  #
  # Reading by index is the fix that survives the next field being added.
  defp translate_gl_canvas_event(_source, event)
       when is_tuple(event) and elem(event, 0) == :wxMouse and tuple_size(event) >= 12 do
    type = elem(event, 1)
    x = elem(event, 2)
    y = elem(event, 3)
    ctrl = elem(event, 7)
    shift = elem(event, 8)
    alt = elem(event, 9)
    meta = elem(event, 10)
    wheel_rotation = elem(event, 11)

    modifiers = modifiers(ctrl, shift, alt, meta)

    case type do
      :motion -> {:wx_mouse, :move, x, y, nil, nil, []}
      :left_down -> {:wx_mouse, :down, x, y, :left, nil, modifiers}
      :middle_down -> {:wx_mouse, :down, x, y, :middle, nil, modifiers}
      :right_down -> {:wx_mouse, :down, x, y, :right, nil, modifiers}
      :left_up -> {:wx_mouse, :up, x, y, :left, nil, modifiers}
      :middle_up -> {:wx_mouse, :up, x, y, :middle, nil, modifiers}
      :right_up -> {:wx_mouse, :up, x, y, :right, nil, modifiers}
      :left_dclick -> {:wx_mouse, :double_click, x, y, :left, nil, modifiers}
      :mousewheel -> {:wx_mouse, :wheel, x, y, nil, wheel_rotation, modifiers}
      :enter_window -> {:wx_mouse, :enter, x, y, nil, nil, []}
      :leave_window -> {:wx_mouse, :leave, x, y, nil, nil, []}
      _other -> nil
    end
  end

  # Key events
  defp translate_gl_canvas_event(
         _source,
         {:wxKey, :key_down, keycode, _, ctrl, shift, alt, meta, unicode_char, _raw}
       ) do
    char = if unicode_char > 0, do: <<unicode_char::utf8>>, else: nil
    {:wx_key, :down, keycode, char, modifiers(ctrl, shift, alt, meta)}
  end

  defp translate_gl_canvas_event(
         _source,
         {:wxKey, :key_up, keycode, _, ctrl, shift, alt, meta, unicode_char, _raw}
       ) do
    char = if unicode_char > 0, do: <<unicode_char::utf8>>, else: nil
    {:wx_key, :up, keycode, char, modifiers(ctrl, shift, alt, meta)}
  end

  # Focus events
  defp translate_gl_canvas_event(_source, {:wxFocus, :set_focus, _}) do
    {:wx_focus, :gained}
  end

  defp translate_gl_canvas_event(_source, {:wxFocus, :kill_focus, _}) do
    {:wx_focus, :lost}
  end

  # Paint event - just triggers a render, no data needed
  defp translate_gl_canvas_event(_source, {:wxPaint, :paint}) do
    :request_render
  end

  # Unknown event
  defp translate_gl_canvas_event(_source, event) do
    Logger.debug("Renderer: unhandled GL canvas event #{inspect(event)}")
    nil
  end

  defp modifiers(ctrl, shift, alt, meta) do
    []
    |> maybe_add(:ctrl, ctrl)
    |> maybe_add(:shift, shift)
    |> maybe_add(:alt, alt)
    |> maybe_add(:meta, meta)
  end

  defp maybe_add(list, key, true), do: [key | list]
  defp maybe_add(list, _key, _), do: list

  defp get_dpi_scale(source) do
    try do
      :wxWindow.getContentScaleFactor(source)
    rescue
      _ -> 1.0
    catch
      _, _ -> 1.0
    end
  end

  ## ------------------------------------------------------------------
  ## Helpers
  ## ------------------------------------------------------------------

  defp init_opengl_nif do
    # On some macOS/wx combinations the gl module's on_load does not fire
    # automatically and the NIF must be initialised explicitly.
    #
    # Both entry points are version-dependent: :gl.init_nif/0 does not exist on
    # OTP 29 / wx-2.6, where the NIF initialises itself. Its absence is normal,
    # not a failure, so it is gated rather than caught - the previous version
    # warned on every startup and, worse, the raised UndefinedFunctionError
    # meant :wxe_master.init_opengl/0 on the following line never ran at all.
    #
    # apply/3 keeps the compiler from warning about a function that legitimately
    # may not exist.
    Enum.each([{:gl, :init_nif}, {:wxe_master, :init_opengl}], fn {module, function} ->
      Code.ensure_loaded(module)

      if function_exported?(module, function, 0) do
        try do
          apply(module, function, [])
          Logger.debug("Renderer: #{inspect(module)}.#{function}/0 ok")
        catch
          kind, reason ->
            Logger.warning(
              "Renderer: #{inspect(module)}.#{function}/0 failed " <>
                "(#{inspect(kind)}: #{inspect(reason)}) - GL canvases may not work"
            )
        end
      else
        Logger.debug(
          "Renderer: #{inspect(module)}.#{function}/0 not present on this OTP, skipping"
        )
      end
    end)
  end

  defp detect_mode do
    {r, g, b, _a} = :wxSystemSettings.getColour(5)
    avg = div(r + g + b, 3)
    if avg > 128, do: :light, else: :dark
  end

  # `:wx.new/0` raises {:load_driver, ~c"No driver found"} when the Erlang
  # install was built without wxWidgets. That message says nothing about the
  # cause and is the first thing a new user hits on a machine whose OTP came
  # from a source build or a minimal package, so it is worth translating once
  # here rather than being answered repeatedly in an issue tracker.
  defp new_wx! do
    :wx.new()
  rescue
    e in ErlangError ->
      case e.original do
        {:load_driver, _} ->
          reraise """
                  wxWidgets is not available in this Erlang install.

                  cedar needs an Erlang/OTP built with wxWidgets support, and
                  `:wx.new()` could not load its driver. This is a property of
                  how Erlang was built, not of your project.

                  Erlang #{System.otp_release()}, wx #{wx_vsn()}.

                  With asdf or kerl, rebuild Erlang with wx present first - on
                  macOS `brew install wxwidgets`, on Debian/Ubuntu
                  `apt install libwxgtk3.2-dev`. A prebuilt Erlang from a
                  distribution package usually already has it.
                  """,
                  __STACKTRACE__

        _other ->
          reraise e, __STACKTRACE__
      end
  end

  defp wx_vsn do
    case Application.spec(:wx, :vsn) do
      nil -> "not loaded"
      vsn -> to_string(vsn)
    end
  end
end
