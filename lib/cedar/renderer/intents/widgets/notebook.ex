defmodule Cedar.Renderer.Intents.Widgets.Notebook do
  use WxEx
  require Logger

  def apply({:ensure_widget, widget_id, :notebook, parent_id, opts}, state) do
    if Map.has_key?(state.notebooks, widget_id) do
      state
    else
      parent =
        Map.get(state.windows, parent_id) ||
          Map.get(state.panels, parent_id)

      if is_nil(parent) do
        Logger.debug("Renderer: parent not ready for notebook #{inspect(widget_id)}")
        state
      else
        notebook =
          :wxNotebook.new(
            parent,
            wxID_ANY()
          )

        # A notebook used as a ribbon is a fixed-height strip, not something
        # that grows with its busiest page. Without a minimum size it takes its
        # best size from whichever tab has the most in it, so adding a longer
        # list to one tab silently makes the whole bar taller.
        case Keyword.get(opts, :size) do
          {w, h} -> :wxWindow.setMinSize(notebook, {w, h})
          _ -> :ok
        end

        parent_sizer = Map.fetch!(state.sizers, parent_id)

        :wxSizer.add(parent_sizer, notebook, proportion: 1, flag: wxEXPAND())
        :wxWindow.layout(parent)

        :wxEvtHandler.connect(notebook, :command_notebook_page_changed)

        %{
          state
          | notebooks: Map.put(state.notebooks, widget_id, notebook),
            widget_ids: Map.put(state.widget_ids, notebook, widget_id)
        }
      end
    end
  end
end
