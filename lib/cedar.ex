defmodule Cedar do
  @moduledoc """
  cedar - Model-View-Update framework for wxWidgets in Elixir.

  ## Usage

  Add cedar as a dependency. It starts automatically as an OTP application.

  Define scenes using `Cedar.Scene`:

      defmodule MyApp.Scenes.Main do
        use Cedar.Scene

        def init(_opts) do
          %{counter: 0}
        end

        def handle_event({:ui_event, :increment, :click}, model) do
          %{model | counter: model.counter + 1}
        end

        def handle_event(_event, model), do: model

        def view(model) do
          [
            {:ensure_window, :main, title: "Counter"},
            {:ensure_panel, :root, :main, []},
            {:ensure_widget, :label, :static_text, :root, label: "Count: \#{model.counter}"},
            {:ensure_widget, :increment, :button, :root, label: "+1"},
            {:layout, :root, {:vbox, [], [:label, :increment]}},
            {:refresh, :main}
          ]
        end
      end

  Start your scene:

      Cedar.start_scene(MyApp.Scenes.Main)

  """

  @doc """
  Starts a scene process under the cedar supervision tree.

  The module must `use Cedar.Scene` and implement the scene callbacks:
  - `init/1` - Returns initial model
  - `handle_event/2` - Handles events, returns updated model
  - `view/1` - Returns list of intents

  ## Options

  - `:args` - Arguments passed to the scene's `init/1` callback (default: `%{}`)

  ## Examples

      Cedar.start_scene(MyApp.Scenes.Config)
      Cedar.start_scene(MyApp.Scenes.Config, args: %{theme: :dark})

  """
  @spec start_scene(module(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_scene(module, opts \\ []) do
    args = Keyword.get(opts, :args, %{})

    child_spec = %{
      id: module,
      start: {Cedar.Scene.Server, :start_link, [{module, args}]},
      restart: :permanent
    }

    DynamicSupervisor.start_child(Cedar.SceneSupervisor, child_spec)
  end

  @doc """
  Stops a running scene.

  ## Examples

      Cedar.stop_scene(MyApp.Scenes.Config)

  """
  @spec stop_scene(module()) :: :ok | {:error, :not_found}
  def stop_scene(module) do
    case Process.whereis(module) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(Cedar.SceneSupervisor, pid)
    end
  end

  @doc """
  Lists all running scene modules.

  ## Examples

      Cedar.list_scenes()
      #=> [MyApp.Scenes.UI, MyApp.Scenes.Config]

  """
  @spec list_scenes() :: [module()]
  def list_scenes do
    Cedar.SceneSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} ->
      {:registered_name, name} = Process.info(pid, :registered_name)
      name
    end)
    |> Enum.filter(&is_atom/1)
  end

  @doc """
  Sets the theme for the renderer.

  ## Examples

      Cedar.set_theme(MyApp.Theme)

  """
  @spec set_theme(module()) :: :ok
  def set_theme(theme_module) do
    Cedar.Renderer.set_theme(theme_module)
  end
end
