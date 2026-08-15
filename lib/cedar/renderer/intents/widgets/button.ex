defmodule Cedar.Renderer.Intents.Widgets.Button do
  use WxEx
  require Logger

  def apply({:ensure_widget, widget_id, :button, parent_id, opts}, state) do
    if Map.has_key?(state.widgets, widget_id) do
      state
    else
      parent = Map.get(state.panels, parent_id)

      if is_nil(parent) do
        Logger.debug("Renderer: parent not ready for button #{inspect(widget_id)}")
        state
      else
        label = Keyword.get(opts, :label, "")
        align = Keyword.get(opts, :align, :center)

        widget =
          :wxButton.new(
            parent,
            wxID_ANY(),
            label: label
          )

        parent_sizer = Map.fetch!(state.sizers, parent_id)

        flag = Bitwise.bor(wxALL(), align_flag(align))

        :wxSizer.add(
          parent_sizer,
          widget,
          proportion: 0,
          flag: flag,
          border: 6
        )

        connect(widget, Keyword.get(opts, :hold, false))

        :wxWindow.layout(parent)

        %{
          state
          | widgets: Map.put(state.widgets, widget_id, widget),
            widget_ids: Map.put(state.widget_ids, widget, widget_id)
        }
      end
    end
  end

  # A button that is *held* rather than pressed.
  #
  # Some controls are a command — "save", "reset" — and a click is the whole
  # story. A jog is not one of those: the machine moves for as long as the
  # operator holds the button down, so the interesting facts are when the
  # button went down and when it came up, and a click event reports neither.
  #
  # `:leave_window` is reported as a release on purpose. A finger that slides
  # off a jog button is a finger that has let go, and the alternative — an axis
  # that keeps moving because the pointer wandered two pixels while the button
  # was down — is the exact failure the hold-to-run pattern exists to prevent.
  # A spurious release costs nothing: stopping something already stopped is
  # free, and stopping is always the safe direction to be wrong in.
  #
  # `skip: true` so the native button still draws itself pressed. The event is
  # being observed, not intercepted.
  defp connect(widget, true) do
    :wxEvtHandler.connect(widget, :left_down, skip: true)
    :wxEvtHandler.connect(widget, :left_up, skip: true)
    :wxEvtHandler.connect(widget, :leave_window, skip: true)
  end

  defp connect(widget, false) do
    :wxEvtHandler.connect(widget, :command_button_clicked)
  end

  defp align_flag(:center), do: wxALIGN_CENTER_HORIZONTAL()
  defp align_flag(:left), do: wxALIGN_LEFT()
  defp align_flag(:right), do: wxALIGN_RIGHT()
  defp align_flag(:expand), do: wxEXPAND()
  defp align_flag(_), do: wxALIGN_CENTER_HORIZONTAL()
end
