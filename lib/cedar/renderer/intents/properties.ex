defmodule Cedar.Renderer.Intents.Properties do
  use WxEx

  def apply({:set, widget_id, props}, state) do
    case Map.get(state.widgets, widget_id) do
      nil ->
        state

      widget ->
        case Map.get(Map.get(state, :composites, %{}), widget_id) do
          nil ->
            Enum.each(props, fn {key, value} ->
              set_property(widget, key, value)
            end)

          parts ->
            Enum.each(props, fn {key, value} ->
              set_composite_property(parts, key, value)
            end)
        end

        state
    end
  end

  # Composite widgets split their properties over inner parts; anything
  # unrecognised lands on the panel, so :enabled and :visible keep their
  # ordinary meaning. :colour_field parts are handled here; :pick_field
  # (a lone combo, `%{combo: _}`) delegates to its own module.
  defp set_composite_property(%{combo: _} = parts, key, value),
    do: Cedar.Renderer.Intents.Widgets.PickField.set(parts, key, value)

  defp set_composite_property(parts, :value, value) when is_binary(value) do
    # changeValue, not setValue: it does not emit a change event, so a set
    # that echoes what the person just typed cannot loop; the equality guard
    # keeps the caret from jumping on the echo.
    if :wxTextCtrl.getValue(parts.text) != String.to_charlist(value) do
      :wxTextCtrl.changeValue(parts.text, value)
    end
  end

  defp set_composite_property(parts, :colour, {r, g, b}) do
    :wxColourPickerCtrl.setColour(parts.pick, {r, g, b})
  end

  defp set_composite_property(parts, :picker_visible, visible) when is_boolean(visible) do
    :wxWindow.show(parts.pick, show: visible)
    :wxWindow.layout(parts.panel)
  end

  defp set_composite_property(parts, key, value), do: set_property(parts.panel, key, value)

  @doc false
  def set_plain(widget, key, value), do: set_property(widget, key, value)

  defp set_property(widget, :text, value) when is_binary(value) do
    try do
      :wxStatusBar.setStatusText(widget, value)
    catch
      _, _ -> :wxStaticText.setLabel(widget, value)
    end
  end

  defp set_property(widget, :value, value) when is_binary(value) do
    :wxTextCtrl.setValue(widget, value)
  end

  defp set_property(widget, :value, value) when is_integer(value) do
    try do
      :wxGauge.setValue(widget, value)
    catch
      _, _ ->
        try do
          :wxSpinCtrl.setValue(widget, value)
        catch
          _, _ -> :wxSlider.setValue(widget, value)
        end
    end
  end

  defp set_property(widget, :value, value) when is_boolean(value) do
    try do
      :wxToggleButton.setValue(widget, value)
    catch
      _, _ -> :wxCheckBox.setValue(widget, value)
    end
  end

  defp set_property(widget, :selected, nil) do
    # Clear selection
    try do
      :wxChoice.setSelection(widget, -1)
    catch
      _, _ -> :ok
    end
  end

  defp set_property(widget, :selected, value) when is_integer(value) do
    try do
      :wxListBox.setSelection(widget, value)
    catch
      _, _ ->
        try do
          :wxChoice.setSelection(widget, value)
        catch
          _, _ -> :wxRadioBox.setSelection(widget, value)
        end
    end
  end

  # Show or hide a widget in place. Sizers skip hidden windows, so the row
  # reflows around it - which is why this property relayouts the parent:
  # a widget that vanished without a reflow leaves its hole behind.
  defp set_property(widget, :visible, visible) when is_boolean(visible) do
    :wxWindow.show(widget, show: visible)

    case :wxWindow.getParent(widget) do
      {:wx_ref, 0, _, _} -> :ok
      parent -> :wxWindow.layout(parent)
    end
  end

  # The swatch on a colour picker. Only ever set on :colour_picker widgets;
  # wx dispatches by the ref's class, so a stray set on another type raises
  # rather than silently no-opping, which is the better failure.
  defp set_property(widget, :colour, {r, g, b}) do
    :wxColourPickerCtrl.setColour(widget, {r, g, b})
  end

  defp set_property(widget, :items, items) when is_list(items) do
    try do
      :wxListBox.clear(widget)
      Enum.each(items, &:wxListBox.append(widget, to_string(&1)))
    catch
      _, _ ->
        :wxChoice.clear(widget)
        Enum.each(items, &:wxChoice.append(widget, to_string(&1)))
    end
  end

  defp set_property(widget, :range, value) when is_integer(value) do
    :wxGauge.setRange(widget, value)
  end

  defp set_property(_widget, _key, _value), do: :ok
end
