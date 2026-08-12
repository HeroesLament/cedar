defmodule WxMVU.Visual.ImageTest do
  @moduledoc """
  Exercises `Visual.Image` against a real context.

  This is the first test of the visuals layer as a whole: one call chain builds
  a program, a fullscreen quad, a data texture and a colormap texture, feeds it
  data, draws, and reads the pixels back. Everything below it — Program,
  Std140, Geometry, Texture, Colormap, and the generated GLSL — has to be right
  for these to pass.
  """

  use WxMVU.GLCase

  alias WxMVU.Visual
  alias WxMVU.Visual.Frame

  @size 4

  # domain -100..0 with a red-to-blue colormap: -100 renders red, 0 renders
  # blue, so a pixel's colour reads straight back as its value.
  defp waterfall(opts \\ []) do
    defaults = [
      grid: {1, @size},
      domain: {-100.0, 0.0},
      colormap: [{0.0, {255, 0, 0}}, {1.0, {0, 0, 255}}],
      advance: :per_datum
    ]

    {:ok, state} = Visual.Image.init(%{}, Keyword.merge(defaults, opts))
    state
  end

  defp draw(state) do
    clear()

    {:ok, state} =
      Visual.Image.draw(state, %Frame{
        pixel_size: {@size, @size},
        logical_size: {@size, @size},
        dpi_scale: 1.0
      })

    state
  end

  defp column, do: for(row <- 0..(@size - 1), do: pixel(@size, 0, row))

  defp frame(size) do
    %Frame{pixel_size: {size, size}, logical_size: {size, size}, dpi_scale: 1.0}
  end

  setup do
    fbo = offscreen(@size)
    %{fbo: fbo}
  end

  describe "init/2" do
    test "builds every resource from a declaration" do
      state = waterfall()

      assert state.grid == {1, @size}
      assert state.domain == {-100.0, 0.0}
      assert state.current_row == 0

      # The whole point: no program, buffer or texture was named by the caller.
      assert state.program.blocks[:per_frame].size == 16
      assert state.geometry.stride == 16
      assert state.data.format == :r32f

      Visual.Image.destroy(state)
    end

    test "fills with the domain minimum by default" do
      state = waterfall() |> draw()

      # Every cell starts at the fill value, which maps to the low end.
      assert Enum.all?(column(), &close?(elem(&1, 0), 255))

      Visual.Image.destroy(state)
    end

    test "requires a grid and a domain" do
      assert_raise ArgumentError, ~r/requires a :grid/, fn ->
        Visual.Image.init(%{}, domain: {0.0, 1.0})
      end

      assert_raise ArgumentError, ~r/requires a :domain/, fn ->
        Visual.Image.init(%{}, grid: {4, 4})
      end
    end

    test "rejects a nonsense advance mode" do
      assert_raise ArgumentError, ~r/:advance must be/, fn ->
        Visual.Image.init(%{}, grid: {1, 4}, domain: {0.0, 1.0}, advance: :sideways)
      end
    end
  end

  describe "handle_data/2" do
    test "a row lands where the ring buffer is pointing", %{} do
      state = waterfall()

      # Row 0 is the bottom of the texture; write the domain maximum there.
      {:ok, state} = Visual.Image.handle_data(state, {:row, floats([0.0])})
      state = draw(state)

      assert state.current_row == 1

      Visual.Image.destroy(state)
    end

    test "successive rows advance and scroll", %{} do
      state = waterfall()

      # Fill every row with the maximum, one row at a time.
      state =
        Enum.reduce(0..(@size - 1), state, fn _i, acc ->
          {:ok, next} = Visual.Image.handle_data(acc, {:row, floats([0.0])})
          next
        end)

      assert state.current_row == 0, "the ring buffer should have wrapped"

      state = draw(state)
      assert Enum.all?(column(), &close?(elem(&1, 2), 255)), "every row should read as blue"

      Visual.Image.destroy(state)
    end

    test "advance: :none leaves the write position alone" do
      state = waterfall(advance: :none)

      {:ok, state} = Visual.Image.handle_data(state, {:row, floats([0.0])})
      {:ok, state} = Visual.Image.handle_data(state, {:row, floats([0.0])})

      assert state.current_row == 0

      Visual.Image.destroy(state)
    end

    test "a whole grid can be uploaded at once" do
      state = waterfall(advance: :none)

      {:ok, state} =
        Visual.Image.handle_data(state, {:grid, floats([-100.0, -100.0, 0.0, 0.0])})

      state = draw(state)
      [bottom, _, _, top] = column()

      assert close?(elem(bottom, 0), 255), "the first rows are the domain minimum: red"
      assert close?(elem(top, 2), 255), "the last rows are the domain maximum: blue"

      Visual.Image.destroy(state)
    end

    test "a wrong-sized grid is rejected rather than smeared" do
      state = waterfall(advance: :none)

      assert_raise ArgumentError, ~r/is 16 bytes, got 8/, fn ->
        Visual.Image.handle_data(state, {:grid, floats([0.0, 0.0])})
      end

      Visual.Image.destroy(state)
    end

    test "a short row is padded rather than dropped" do
      # FFT sizes drift at the edges of a stream; showing a frame slightly
      # wrong beats dropping it.
      state = waterfall(grid: {4, @size})

      {:ok, state} = Visual.Image.handle_data(state, {:row, floats([0.0, 0.0])})
      assert state.current_row == 1

      Visual.Image.destroy(state)
    end

    test "clear resets both the contents and the write position" do
      state = waterfall()

      {:ok, state} = Visual.Image.handle_data(state, {:row, floats([0.0])})
      {:ok, state} = Visual.Image.handle_data(state, :clear)

      assert state.current_row == 0

      state = draw(state)
      assert Enum.all?(column(), &close?(elem(&1, 0), 255)), "everything back to the floor"

      Visual.Image.destroy(state)
    end
  end

  describe "update/2" do
    test "a changed domain is a uniform write, not a rebuild" do
      state = waterfall(advance: :none)

      {:ok, state} =
        Visual.Image.handle_data(state, {:grid, floats([-50.0, -50.0, -50.0, -50.0])})

      # -50 sits halfway through -100..0, so it renders halfway along the ramp.
      state = draw(state)
      {r, _g, _b} = pixel(@size, 0, 0)
      assert close?(r, 128, 10)

      # Narrow the domain so -50 is now the minimum, and it should read red.
      {:ok, state} = Visual.Image.update(state, domain: {-50.0, 0.0})
      state = draw(state)
      assert close?(elem(pixel(@size, 0, 0), 0), 255)

      Visual.Image.destroy(state)
    end

    test "a changed colormap changes what is drawn" do
      # Asserting on the texture *id* would be wrong: GL reuses freed names, so
      # deleting one texture and creating another legitimately returns the same
      # id. What matters is the pixels.
      green = [{0.0, {0, 0, 0}}, {1.0, {0, 255, 0}}]

      state = waterfall(advance: :none)
      {:ok, state} = Visual.Image.handle_data(state, {:grid, floats([0.0, 0.0, 0.0, 0.0])})

      state = draw(state)
      assert close?(elem(pixel(@size, 0, 0), 2), 255), "the red-to-blue ramp ends blue"

      {:ok, state} = Visual.Image.update(state, colormap: green)
      state = draw(state)

      {r, g, b} = pixel(@size, 0, 0)
      assert close?(g, 255), "the new ramp ends green"
      assert close?(r, 0) and close?(b, 0)
      assert state.colormap == green

      Visual.Image.destroy(state)
    end

    test "an unchanged colormap keeps the same texture" do
      state = waterfall()
      original = state.colormap_texture.id

      {:ok, state} = Visual.Image.update(state, domain: {-80.0, 0.0})

      assert state.colormap_texture.id == original

      Visual.Image.destroy(state)
    end

    test "a changed grid asks to be rebuilt rather than resizing in place" do
      state = waterfall()

      assert {:reinit, {:grid_changed, {1, 4}, {2, 8}}} =
               Visual.Image.update(state, grid: {2, 8})

      Visual.Image.destroy(state)
    end
  end

  describe "Visual.Line" do
    setup do
      fbo = offscreen(16)
      %{fbo: fbo}
    end

    test "draws nothing until it has two points" do
      {:ok, state} = Visual.Line.init(%{}, color: {1.0, 0.0, 0.0, 1.0}, width: 4.0)

      clear()
      {:ok, state} = Visual.Line.draw(state, frame(16))

      assert Enum.all?(red_channel(16), &(&1 == 0))

      Visual.Line.destroy(state)
    end

    test "a horizontal line covers rows in proportion to its width" do
      {:ok, state} = Visual.Line.init(%{}, color: {1.0, 0.0, 0.0, 1.0}, width: 4.0)
      {:ok, state} = Visual.Line.handle_data(state, {:points, [{-0.8, 0.0}, {0.8, 0.0}]})

      clear()
      {:ok, state} = Visual.Line.draw(state, frame(16))

      lit = Enum.count(0..15, fn row -> elem(pixel(16, 8, row), 0) == 255 end)
      assert lit == 4, "a 4px line should cover 4 rows, covered #{lit}"

      Visual.Line.destroy(state)
    end

    test "width is a live uniform, not baked into the geometry" do
      {:ok, state} = Visual.Line.init(%{}, color: {1.0, 0.0, 0.0, 1.0}, width: 2.0)
      {:ok, state} = Visual.Line.handle_data(state, {:points, [{-0.8, 0.0}, {0.8, 0.0}]})

      clear()
      {:ok, state} = Visual.Line.draw(state, frame(16))
      thin = Enum.count(0..15, fn row -> elem(pixel(16, 8, row), 0) == 255 end)

      {:ok, state} = Visual.Line.update(state, width: 6.0)
      clear()
      {:ok, state} = Visual.Line.draw(state, frame(16))
      thick = Enum.count(0..15, fn row -> elem(pixel(16, 8, row), 0) == 255 end)

      assert thick > thin, "#{thin} -> #{thick}"

      Visual.Line.destroy(state)
    end

    test "clear empties the geometry" do
      {:ok, state} = Visual.Line.init(%{}, color: {1.0, 0.0, 0.0, 1.0}, width: 4.0)
      {:ok, state} = Visual.Line.handle_data(state, {:points, [{-0.8, 0.0}, {0.8, 0.0}]})
      {:ok, state} = Visual.Line.handle_data(state, :clear)

      clear()
      {:ok, state} = Visual.Line.draw(state, frame(16))

      assert Enum.all?(red_channel(16), &(&1 == 0))

      Visual.Line.destroy(state)
    end
  end

  describe "Visual.Grid" do
    setup do
      fbo = offscreen(32)
      %{fbo: fbo}
    end

    test "draws lines against a background" do
      {:ok, state} =
        Visual.Grid.init(%{},
          spacing: {0.25, 0.25},
          thickness: 2.0,
          line_color: {1.0, 0.0, 0.0, 1.0},
          background: {0.0, 0.0, 1.0, 1.0}
        )

      clear()
      {:ok, state} = Visual.Grid.draw(state, frame(32))

      reds = red_channel(32)
      lit = Enum.count(reds, &(&1 > 32))

      assert lit > 0, "no gridlines drawn"
      assert lit < div(32 * 32, 2), "the grid filled the frame"

      Visual.Grid.destroy(state)
    end

    test "a one-pixel line stays visible" do
      # Gridlines land on pixel boundaries; a naive coverage model makes
      # hairlines vanish entirely.
      {:ok, state} =
        Visual.Grid.init(%{},
          spacing: {0.25, 0.25},
          thickness: 1.0,
          line_color: {1.0, 0.0, 0.0, 1.0},
          background: {0.0, 0.0, 0.0, 1.0}
        )

      clear()
      {:ok, state} = Visual.Grid.draw(state, frame(32))

      assert Enum.max(red_channel(32)) > 64

      Visual.Grid.destroy(state)
    end

    test "thickness updates without a rebuild" do
      {:ok, state} =
        Visual.Grid.init(%{},
          spacing: {0.25, 0.25},
          thickness: 1.0,
          line_color: {1.0, 0.0, 0.0, 1.0},
          background: {0.0, 0.0, 0.0, 1.0}
        )

      clear()
      {:ok, state} = Visual.Grid.draw(state, frame(32))
      thin = Enum.count(red_channel(32), &(&1 > 32))

      {:ok, state} = Visual.Grid.update(state, thickness: 4.0)
      clear()
      {:ok, state} = Visual.Grid.draw(state, frame(32))
      thick = Enum.count(red_channel(32), &(&1 > 32))

      assert thick > thin, "#{thin} -> #{thick}"

      Visual.Grid.destroy(state)
    end

    test "rejects a nonsense spacing" do
      assert_raise ArgumentError, ~r/:spacing must be/, fn ->
        Visual.Grid.init(%{}, spacing: {0.0, 0.25})
      end
    end
  end

  describe "Visual.Mesh" do
    setup do
      fbo = offscreen(32, depth: true)
      %{fbo: fbo}
    end

    defp lit_pixels(size) do
      Enum.count(red_channel(size), &(&1 > 8))
    end

    test "draws nothing until it has geometry" do
      {:ok, state} = Visual.Mesh.init(%{}, base_color: {1.0, 0.0, 0.0, 1.0})

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))

      assert lit_pixels(32) == 0

      Visual.Mesh.destroy(state)
    end

    test "a box in front of the camera covers pixels" do
      {:ok, state} =
        Visual.Mesh.init(%{},
          mesh: Visual.Mesh.box(2.0),
          eye: {0.0, 0.0, 5.0},
          base_color: {1.0, 0.0, 0.0, 1.0}
        )

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))

      lit = lit_pixels(32)

      assert lit > 0, "the box rendered nothing"
      assert lit < 32 * 32, "the box filled the entire frame"

      Visual.Mesh.destroy(state)
    end

    test "the camera is a live uniform: backing off shrinks the box" do
      # The whole reason the projection is rebuilt per draw rather than baked
      # into the vertex buffer at init.
      {:ok, state} =
        Visual.Mesh.init(%{},
          mesh: Visual.Mesh.box(2.0),
          eye: {0.0, 0.0, 4.0},
          base_color: {1.0, 0.0, 0.0, 1.0}
        )

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))
      near = lit_pixels(32)

      {:ok, state} = Visual.Mesh.update(state, eye: {0.0, 0.0, 12.0})
      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))
      far = lit_pixels(32)

      assert far < near, "#{near} -> #{far}"
      assert far > 0, "the box vanished entirely"

      Visual.Mesh.destroy(state)
    end

    test "lighting varies across faces rather than painting a flat silhouette" do
      # Lambert with an ambient floor: a corner-on box shows at least two
      # distinct brightnesses. A flat result means the normal matrix or the
      # light direction never reached the shader.
      {:ok, state} =
        Visual.Mesh.init(%{},
          mesh: Visual.Mesh.box(2.0),
          eye: {4.0, 3.0, 5.0},
          light_direction: {0.3, 0.9, 0.4},
          base_color: {1.0, 1.0, 1.0, 1.0}
        )

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))

      shades = red_channel(32) |> Enum.reject(&(&1 == 0)) |> Enum.uniq()

      assert length(shades) >= 2, "every lit pixel is #{inspect(shades)}"

      Visual.Mesh.destroy(state)
    end

    test "sending a new mesh replaces the old one" do
      {:ok, state} =
        Visual.Mesh.init(%{},
          mesh: Visual.Mesh.box(0.5),
          eye: {0.0, 0.0, 5.0},
          base_color: {1.0, 0.0, 0.0, 1.0}
        )

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))
      small = lit_pixels(32)

      {:ok, state} = Visual.Mesh.handle_data(state, {:mesh, Visual.Mesh.box(3.0)})
      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))
      large = lit_pixels(32)

      assert large > small, "#{small} -> #{large}"

      Visual.Mesh.destroy(state)
    end

    test "clear empties the geometry" do
      {:ok, state} =
        Visual.Mesh.init(%{},
          mesh: Visual.Mesh.box(2.0),
          eye: {0.0, 0.0, 5.0},
          base_color: {1.0, 0.0, 0.0, 1.0}
        )

      {:ok, state} = Visual.Mesh.handle_data(state, :clear)

      clear()
      GL.clear(:depth)
      {:ok, state} = Visual.Mesh.draw(state, frame(32))

      assert lit_pixels(32) == 0

      Visual.Mesh.destroy(state)
    end
  end

  describe "resolve/1" do
    test "built-in visuals are named by atom, as widgets are" do
      assert Visual.resolve(:image) == WxMVU.Visual.Image
      assert Visual.resolve(:line) == WxMVU.Visual.Line
      assert Visual.resolve(:grid) == WxMVU.Visual.Grid
      assert Visual.resolve(:mesh) == WxMVU.Visual.Mesh
    end

    test "an unknown name says what is available" do
      assert_raise ArgumentError, ~r/unknown visual :nope.*:image.*:custom/s, fn ->
        Visual.resolve(:nope)
      end
    end
  end
end
