defmodule WxMVU.Visual do
  @moduledoc """
  Behaviour for things that draw themselves.

  A visual owns its GPU resources and knows how to render one kind of thing —
  an image, a polyline, a grid, a mesh. Applications name visuals and configure
  them; they do not create programs, allocate buffers, or write GLSL.

      {:ensure_visual, :waterfall, :image, :root,
        grid: {512, 256},
        domain: {-100.0, 0.0},
        colormap: :viridis,
        advance: :per_datum}

  ## Two channels, deliberately

  Configuration arrives through `c:update/2`, driven by the MVU diff: it is a
  pure function of the model, changes rarely, and a change to it is a minimal
  GPU update. Sample data arrives through `c:handle_data/2`, bypassing MVU
  entirely, because pushing 512 floats through `view/1` and the differ at 30 Hz
  would be absurd.

  This is the split `WxMVU.GLCanvas` already makes for canvases. Visuals
  inherit it rather than inventing something new.

  ## Input

  A visual that should respond to the mouse names a process to tell:

      {:ensure_visual, :board, :layers, :root, notify: self(), layers: [...]}

  `view/1` runs in the scene process, so `self()` there is the scene, and
  events arrive at its `handle_event/2` as

      {:ui_event, :board, :mouse, %{type: :down, u: 0.31, v: 0.62, ...}}
      {:ui_event, :board, :resize, %{logical_size: {680, 666}, dpi_scale: 2.0, ...}}

  `u` and `v` are the fraction across the surface rather than pixels, because
  a hit test written against them survives a resize, and because a visual's
  content coordinates are almost never its widget coordinates.

  Note where the game logic then lives: in the scene's model, as ordinary MVU.
  The visual is told what to draw; it does not own what is true. A visual that
  tracked the selected square itself would put half the application's state
  somewhere the model cannot see it.

  ## Implementing one

  Built-in visuals are referenced by atom, exactly as widgets are — `:image`,
  not `WxMVU.Visual.Image`. A module reference is for *your* code, matching the
  `module:` option on `:ensure_gl_canvas`:

      {:ensure_visual, :radar, :custom, :root,
        module: MyApp.Visuals.PolarRadar, opts: [sweep_rate: 30]}

  Implementations should compose `WxMVU.GLCanvas.Draw` — `Program`, `Geometry`,
  `Texture`, `Colormap` — rather than calling `WxMVU.Renderer.GL` directly.
  Reach for raw GL only for something the Draw layer genuinely does not cover,
  and consider whether it should.

  All callbacks run with the GL context current.
  """

  alias WxMVU.Visual.Frame

  @type state :: term()
  @type opts :: keyword()

  @doc """
  Creates GPU resources and returns initial state.

  Called once, with the context current. `opts` is the declaration from the
  scene's intent.
  """
  @callback init(ctx :: map(), opts()) :: {:ok, state()} | {:error, term()}

  @doc """
  Applies a changed declaration.

  Called when the MVU diff sees the visual's options change. Implementations
  should do the minimum: a changed colour range is a uniform write, a changed
  grid size is a reallocation. Returning `{:reinit, reason}` asks the runtime to
  destroy and recreate the visual instead, for changes not worth handling
  incrementally.
  """
  @callback update(state(), opts()) :: {:ok, state()} | {:reinit, term()}

  @doc """
  Receives data sent with `WxMVU.Visual.send_data/2`.

  This is the high-rate path. Keep it cheap: upload and return.
  """
  @callback handle_data(state(), term()) :: {:ok, state()}

  @doc "Draws one frame."
  @callback draw(state(), Frame.t()) :: {:ok, state()}

  @doc "Releases GPU resources. The context is still current."
  @callback destroy(state()) :: :ok

  @optional_callbacks update: 2, handle_data: 2

  defmodule Frame do
    @moduledoc """
    Per-frame information handed to `c:WxMVU.Visual.draw/2`.

    `pixel_size` is the framebuffer size and is what shaders wanting a viewport
    in pixels should be given. `logical_size` is in wx units; the two differ on
    HiDPI displays and confusing them produces geometry at half or double scale.
    """

    @type t :: %__MODULE__{
            pixel_size: {pos_integer(), pos_integer()},
            logical_size: {pos_integer(), pos_integer()},
            dpi_scale: float()
          }

    defstruct [:pixel_size, :logical_size, dpi_scale: 1.0]
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour WxMVU.Visual

      alias WxMVU.GLCanvas.Draw.{Colormap, Geometry, Program, Texture}
      alias WxMVU.Visual.Frame

      @impl true
      def update(state, _opts), do: {:ok, state}

      @impl true
      def handle_data(state, _message), do: {:ok, state}

      defoverridable update: 2, handle_data: 2
    end
  end

  @doc """
  Sends data straight to a visual, bypassing MVU.

      WxMVU.Visual.send_data(:waterfall, {:row, bins})
      WxMVU.Visual.send_data(:constellation, :clear)

  This is the high-rate path. Configuration belongs in the scene's declaration,
  where the differ turns a change into a minimal GPU update; sample data does
  not, because routing it through `view/1` at 30 Hz would be absurd.
  """
  @spec send_data(term(), term()) :: :ok
  defdelegate send_data(visual_id, message), to: WxMVU.GLCanvas

  @doc """
  Requests an immediate redraw.

  The runtime schedules frames on its own; this is for forcing one after a
  change that would otherwise wait for the next tick.
  """
  @spec request_render(term()) :: :ok
  defdelegate request_render(visual_id), to: WxMVU.GLCanvas

  @doc """
  Resolves a built-in visual atom to its module.

  Mirrors how widget types resolve, and keeps framework-provided visuals as
  opaque to applications as `:button` is.
  """
  @spec resolve(atom()) :: module()
  def resolve(:image), do: WxMVU.Visual.Image
  def resolve(:line), do: WxMVU.Visual.Line
  def resolve(:grid), do: WxMVU.Visual.Grid
  def resolve(:mesh), do: WxMVU.Visual.Mesh
  def resolve(:text), do: WxMVU.Visual.Text
  def resolve(:layers), do: WxMVU.Visual.Layers

  def resolve(other) do
    raise ArgumentError,
          "unknown visual #{inspect(other)}. Built-in visuals: " <>
            "[:image, :line, :grid, :mesh, :text, :layers]. For your own, use " <>
            ":custom with " <>
            "module: YourModule."
  end
end
