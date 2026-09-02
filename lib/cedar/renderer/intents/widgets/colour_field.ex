defmodule Cedar.Renderer.Intents.Widgets.ColourField do
  @moduledoc """
  A text field with a colour well inset at its right edge - one widget, one
  id. The composite is a bordered panel that plays the part of the text box;
  inside it a borderless wxTextCtrl takes the width and a small
  wxColourPickerCtrl sits flush right.

      {:ensure_widget, :accent, :colour_field, :root, value: "0xFF8800"}
      {:set, :accent, value: "0xFF8800", colour: {255, 136, 0}, picker_visible: true}

  Events arrive under the composite's id: text edits as `:change` with a
  binary, colour picks as `:change` with the colour tuple - the payload's
  shape says which part the person touched.

  Properties: `:value` (the text), `:colour` (the swatch),
  `:picker_visible` (whether the well shows; hidden, the composite reads as
  a plain text field and the text takes the full width). Anything else
  lands on the panel, so `:enabled` and `:visible` behave like every other
  widget's.
  """

  use WxEx
  require Logger

  def apply({:ensure_widget, widget_id, :colour_field, parent_id, opts}, state) do
    parent = Map.get(state.panels, parent_id) || Map.get(state.windows, parent_id)

    cond do
      is_nil(parent) ->
        Logger.debug("Renderer: parent not ready for colour_field #{inspect(widget_id)}")
        state

      Map.has_key?(state.widgets, widget_id) ->
        state

      true ->
        panel = :wxPanel.new(parent, style: wxBORDER_SIMPLE())

        text =
          :wxTextCtrl.new(panel, wxID_ANY(),
            value: Keyword.get(opts, :value, ""),
            style: wxBORDER_NONE()
          )

        pick = :wxColourPickerCtrl.new(panel, wxID_ANY(), [])
        :wxWindow.setMinSize(pick, {34, -1})

        # The panel is the text box: paint it like the field it contains, so
        # the well appears to float inside one control.
        :wxWindow.setBackgroundColour(panel, :wxWindow.getBackgroundColour(text))

        sizer = :wxBoxSizer.new(wxHORIZONTAL())
        :wxSizer.add(sizer, text, proportion: 1, flag: Bitwise.bor(wxEXPAND(), wxALL()), border: 2)

        :wxSizer.add(sizer, pick,
          proportion: 0,
          flag: Bitwise.bor(wxALIGN_CENTER_VERTICAL(), wxRIGHT()),
          border: 2
        )

        :wxPanel.setSizer(panel, sizer)

        unless Keyword.get(opts, :picker_visible, true) do
          :wxWindow.show(pick, show: false)
        end

        case Map.get(state.sizers, parent_id) do
          nil -> :ok
          parent_sizer -> :wxSizer.add(parent_sizer, panel, proportion: 0, flag: wxEXPAND())
        end

        :wxEvtHandler.connect(text, :command_text_updated)
        :wxEvtHandler.connect(pick, :command_colourpicker_changed)
        :wxWindow.layout(parent)

        # Both inner controls report as the composite's id; the panel is the
        # widget the rest of the renderer (layout, destroy) sees.
        %{
          state
          | widgets: Map.put(state.widgets, widget_id, panel),
            widget_ids:
              state.widget_ids
              |> Map.put(text, widget_id)
              |> Map.put(pick, widget_id),
            composites:
              Map.put(state.composites, widget_id, %{panel: panel, text: text, pick: pick})
        }
    end
  end
end
