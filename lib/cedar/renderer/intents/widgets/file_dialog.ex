defmodule Cedar.Renderer.Intents.Widgets.FileDialog do
  @moduledoc """
  File and directory dialogs.

  ## Paths come back as binaries

  wx returns strings as charlists. `FormDialog` already runs every value it
  collects through `to_string/1`; this module did not, so one dialog family
  handed callers binaries and its neighbour handed them charlists.

  That is not a difference an application can be expected to notice. A caller
  pattern-matching `{:ok, path} when is_binary(path)` — which is the obvious
  thing to write, having used the form dialog first — matched nothing, fell
  through to its own catch-all, and did nothing at all. Silently, because
  there is no clause to run when nothing matches.

  So every path out of here is a binary now, and the two dialog families agree.
  """
  use WxEx
  require Logger

  def apply({:show_dialog, dialog_id, :file_open, parent_id, opts}, state) do
    parent =
      Map.get(state.windows, parent_id) ||
        Map.get(state.panels, parent_id)

    if is_nil(parent) do
      Logger.debug("Renderer: parent not ready for file_dialog #{inspect(dialog_id)}")
      state
    else
      message = Keyword.get(opts, :message, "Open file")
      wildcard = Keyword.get(opts, :wildcard, "*.*")
      default_dir = Keyword.get(opts, :default_dir, "")
      default_file = Keyword.get(opts, :default_file, "")
      style = wxFD_OPEN()

      style = if Keyword.get(opts, :multiple, false), do: Bitwise.bor(style, wxFD_MULTIPLE()), else: style
      style = if Keyword.get(opts, :must_exist, true), do: Bitwise.bor(style, wxFD_FILE_MUST_EXIST()), else: style

      dialog =
        :wxFileDialog.new(
          parent,
          message: message,
          defaultDir: default_dir,
          defaultFile: default_file,
          wildCard: wildcard,
          style: style
        )

      modal_result = :wxFileDialog.showModal(dialog)
      ok_id = wxID_OK()

      result =
        if modal_result == ok_id do
          if Keyword.get(opts, :multiple, false) do
            {:ok, Enum.map(:wxFileDialog.getPaths(dialog), &to_string/1)}
          else
            {:ok, to_string(:wxFileDialog.getPath(dialog))}
          end
        else
          :cancel
        end

      :wxFileDialog.destroy(dialog)

      send(self(), {:dialog_result, dialog_id, result})

      state
    end
  end

  def apply({:show_dialog, dialog_id, :file_save, parent_id, opts}, state) do
    parent =
      Map.get(state.windows, parent_id) ||
        Map.get(state.panels, parent_id)

    if is_nil(parent) do
      Logger.debug("Renderer: parent not ready for file_dialog #{inspect(dialog_id)}")
      state
    else
      message = Keyword.get(opts, :message, "Save file")
      wildcard = Keyword.get(opts, :wildcard, "*.*")
      default_dir = Keyword.get(opts, :default_dir, "")
      default_file = Keyword.get(opts, :default_file, "")
      style = wxFD_SAVE()

      style = if Keyword.get(opts, :overwrite_prompt, true), do: Bitwise.bor(style, wxFD_OVERWRITE_PROMPT()), else: style

      dialog =
        :wxFileDialog.new(
          parent,
          message: message,
          defaultDir: default_dir,
          defaultFile: default_file,
          wildCard: wildcard,
          style: style
        )

      modal_result = :wxFileDialog.showModal(dialog)
      ok_id = wxID_OK()

      result =
        if modal_result == ok_id do
          {:ok, to_string(:wxFileDialog.getPath(dialog))}
        else
          :cancel
        end

      :wxFileDialog.destroy(dialog)

      send(self(), {:dialog_result, dialog_id, result})

      state
    end
  end

  def apply({:show_dialog, dialog_id, :dir, parent_id, opts}, state) do
    parent =
      Map.get(state.windows, parent_id) ||
        Map.get(state.panels, parent_id)

    if is_nil(parent) do
      Logger.debug("Renderer: parent not ready for dir_dialog #{inspect(dialog_id)}")
      state
    else
      message = Keyword.get(opts, :message, "Select directory")
      default_path = Keyword.get(opts, :default_path, "")

      dialog =
        :wxDirDialog.new(
          parent,
          message: message,
          defaultPath: default_path
        )

      modal_result = :wxDirDialog.showModal(dialog)
      ok_id = wxID_OK()

      result =
        if modal_result == ok_id do
          {:ok, to_string(:wxDirDialog.getPath(dialog))}
        else
          :cancel
        end

      :wxDirDialog.destroy(dialog)

      send(self(), {:dialog_result, dialog_id, result})

      state
    end
  end
end
