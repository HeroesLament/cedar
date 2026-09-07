defmodule Cedar.Renderer.Intents.Widgets.PickField do
  @moduledoc """
  A text entry with a dropdown of candidates: type to narrow, pick to fill.
  One editable wxComboBox, one id.

      {:ensure_widget, :tag, :pick_field, :root, value: "start_ok", choices: ["start_ok", "run_sw"]}
      {:set, :tag, value: "st", choices: ["start_ok", "start_btn"]}

  Two event shapes arrive under the id, as with `:colour_field`: `:change`
  with a binary is the person typing, `:change` with an integer is a pick
  from the list - the index into the choices most recently set, which the
  sender still holds, so it maps the index back to a value itself.

  Properties: `:value` (the text; set only when it differs from what is
  shown, so an echo of the typed text never moves the caret), `:choices`
  (replaces the dropdown's items, keeping the text and caret - this is how
  type-to-narrow works: the sender filters, the widget shows). Anything
  else lands on the control, so `:enabled` and `:visible` behave normally.

  Replacing the items goes through Freeze/Thaw and re-applies the text,
  because wxComboBox.clear/1 empties the text as well as the list on every
  platform that matters.
  """

  use WxEx
  require Logger

  def apply({:ensure_widget, widget_id, :pick_field, parent_id, opts}, state) do
    parent = Map.get(state.panels, parent_id) || Map.get(state.windows, parent_id)

    cond do
      is_nil(parent) ->
        Logger.debug("Renderer: parent not ready for pick_field #{inspect(widget_id)}")
        state

      Map.has_key?(state.widgets, widget_id) ->
        state

      true ->
        choices = opts |> Keyword.get(:choices, []) |> Enum.map(&to_string/1)

        combo =
          :wxComboBox.new(parent, wxID_ANY(),
            value: Keyword.get(opts, :value, ""),
            choices: choices,
            style: wxCB_DROPDOWN()
          )

        case Map.get(state.sizers, parent_id) do
          nil -> :ok
          parent_sizer -> :wxSizer.add(parent_sizer, combo, proportion: 0, flag: wxEXPAND())
        end

        :wxEvtHandler.connect(combo, :command_combobox_selected)
        :wxEvtHandler.connect(combo, :command_text_updated)
        :wxEvtHandler.connect(combo, :command_text_enter)
        :wxWindow.layout(parent)

        %{
          state
          | widgets: Map.put(state.widgets, widget_id, combo),
            widget_ids: Map.put(state.widget_ids, combo, widget_id),
            composites: Map.put(state.composites, widget_id, %{combo: combo})
        }
    end
  end

  @doc "Property application for the composite; called from Properties."
  def set(%{combo: combo}, :value, value) when is_binary(value) do
    if :wxComboBox.getValue(combo) != String.to_charlist(value) do
      :wxComboBox.setValue(combo, value)
      :wxComboBox.setInsertionPointEnd(combo)
    end
  end

  def set(%{combo: combo}, :choices, choices) when is_list(choices) do
    wanted = Enum.map(choices, &to_string/1)

    if current_items(combo) != wanted do
      text = :wxComboBox.getValue(combo)
      point = :wxComboBox.getInsertionPoint(combo)
      :wxWindow.freeze(combo)
      :wxComboBox.clear(combo)
      Enum.each(wanted, &:wxComboBox.append(combo, &1))
      :wxComboBox.setValue(combo, text)
      :wxComboBox.setInsertionPoint(combo, point)
      :wxWindow.thaw(combo)
    end
  end

  def set(%{combo: combo}, key, value), do: Cedar.Renderer.Intents.Properties.set_plain(combo, key, value)

  defp current_items(combo) do
    count = :wxComboBox.getCount(combo)
    if count == 0, do: [], else: Enum.map(0..(count - 1), &to_string(:wxComboBox.getString(combo, &1)))
  end
end
