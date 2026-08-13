defmodule Cedar.Application do
  @moduledoc """
  OTP Application for cedar.

  Starts the supervision tree containing:
  - Renderer (owns wx environment)
  - ComponentRegistry (maps widget_id -> scene pid)
  - Coordinator (batches and diffs intents)
  - SceneSupervisor (DynamicSupervisor for scene processes)
  - GLCanvas.Registry (process registry for GL canvases)
  - GLCanvasSupervisor (DynamicSupervisor for GL canvas processes)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core registries
      Cedar.Renderer.ComponentRegistry,
      {Registry, keys: :unique, name: Cedar.GLCanvas.Registry},

      # Renderer - owns wx environment
      Cedar.Renderer,

      # Coordinator - batches and diffs intents
      Cedar.Coordinator,

      # Dynamic supervisors for scenes and canvases
      {DynamicSupervisor, name: Cedar.SceneSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Cedar.GLCanvasSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Cedar.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
