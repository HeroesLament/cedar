defmodule Cedar.Renderer.Intents.Window do
  use WxEx
  require Logger

  def apply({:ensure_window, window_id, opts}, state) do
      if Map.has_key?(state.windows, window_id) do
        state
      else
        title = Keyword.get(opts, :title, Atom.to_string(window_id))
        size = Keyword.get(opts, :size, {1024, 768})
        style = window_style(Keyword.get(opts, :style, :normal))

        frame =
          :wxFrame.new(
            state.wx,
            wxID_ANY(),
            title,
            size: size,
            style: style
          )

        sizer = :wxBoxSizer.new(wxVERTICAL())
        :wxFrame.setSizer(frame, sizer)

        # Centred before showing, not after: a window that appears at the
        # top-left and then jumps to the middle is a visible flicker, and it is
        # the first thing a user sees.
        if Keyword.get(opts, :centre, Keyword.get(opts, :style, :normal) != :normal) do
          :wxFrame.centre(frame)
        end

        :wxFrame.show(frame)

        # Subscribe to window close event
        :wxFrame.connect(frame, :close_window)

        %{
          state
          | windows: Map.put(state.windows, window_id, frame),
            sizers: Map.put(state.sizers, window_id, sizer),
            widget_ids: Map.put(state.widget_ids, frame, window_id)
        }
    end
  end

  def apply({:update_window, window_id, opts}, state) do
    case Map.get(state.windows, window_id) do
      nil ->
        Logger.debug("Renderer: cannot update non-existent window #{inspect(window_id)}")
        state

      frame ->
        if title = Keyword.get(opts, :title) do
          :wxFrame.setTitle(frame, title)
        end

        if size = Keyword.get(opts, :size) do
          :wxFrame.setSize(frame, size)
        end

        state
    end
  end

  def apply({:destroy_window, window_id}, state) do
    case Map.get(state.windows, window_id) do
      nil ->
        state

      frame ->
        # Before the frame, not after. A wxAuiManager must be uninitialised
        # while the window it manages still exists; the other order is an
        # assertion failure inside wxWidgets, at exit, with no Elixir stack
        # trace to say which window caused it.
        state = Cedar.Renderer.Intents.Dock.teardown_for_window(window_id, state)

        :wxFrame.destroy(frame)

        %{
          state
          | windows: Map.delete(state.windows, window_id),
            sizers: Map.delete(state.sizers, window_id)
        }
    end
  end

  def apply({:refresh, window_id}, state) do
    case Map.get(state.windows, window_id) do
      nil ->
        state

      window ->
        :wxWindow.layout(window)
        :wxWindow.refresh(window)
        :wxWindow.update(window)

        # Any dock host that gained panes since the last refresh. They were
        # laid out when their panels were still empty; this is the first moment
        # their contents exist. See Cedar.Renderer.Intents.Dock.refresh/1.
        Cedar.Renderer.Intents.Dock.refresh(state)
    end
  end

  # ==========================================================================

  @doc false
  # Window kinds, named rather than spelled as wx style flags.
  #
  #   :normal   an ordinary application window
  #   :splash   borderless, centred, above other windows - a startup screen
  #   :tool     a small floating palette that stays above its owner
  #   :frameless  no decoration at all, but still resizable and ordinary
  #
  # Named because the flag combinations are neither memorable nor obvious:
  # a splash is not one flag but the *absence* of the caption, border, resize
  # handle and taskbar entry that wxDEFAULT_FRAME_STYLE bundles together, plus
  # stay-on-top. Spelling that out at every call site is how a splash ends up
  # with a close button on one platform and not another.
  defp window_style(:normal), do: wxDEFAULT_FRAME_STYLE()

  defp window_style(:splash) do
    Bitwise.bor(wxFRAME_NO_TASKBAR(), Bitwise.bor(wxSTAY_ON_TOP(), wxBORDER_NONE()))
  end

  defp window_style(:tool) do
    Bitwise.bor(wxFRAME_TOOL_WINDOW(), Bitwise.bor(wxCAPTION(), wxCLOSE_BOX()))
  end

  defp window_style(:frameless), do: wxBORDER_NONE()

  defp window_style(other) do
    raise ArgumentError,
          "unknown window style #{inspect(other)}; " <>
            "known: :normal, :splash, :tool, :frameless"
  end
end
