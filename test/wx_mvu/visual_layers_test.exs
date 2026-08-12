defmodule WxMVU.Visual.LayersTest do
  @moduledoc """
  Layer declaration handling, without a GL context.

  The stacking itself is covered by the `:gl` render tests; this is the part
  that decides what a declaration *means*, where a mistake shows up as a
  missing overlay rather than as an error.
  """

  use ExUnit.Case, async: true

  alias WxMVU.Visual.Layers

  describe "fetch_layers!/1" do
    test "resolves built-in types by atom" do
      layers = Layers.fetch_layers!(layers: [back: :grid, front: :line])

      assert [{:back, WxMVU.Visual.Grid, []}, {:front, WxMVU.Visual.Line, []}] = layers
    end

    test "carries each layer's options" do
      [{:history, WxMVU.Visual.Image, opts}] =
        Layers.fetch_layers!(layers: [history: {:image, grid: {8, 8}, colormap: :turbo}])

      assert opts[:grid] == {8, 8}
      assert opts[:colormap] == :turbo
    end

    test "preserves declaration order, because that is the draw order" do
      layers = Layers.fetch_layers!(layers: [a: :grid, b: :line, c: :grid])

      assert Enum.map(layers, &elem(&1, 0)) == [:a, :b, :c]
    end

    test "accepts a module for your own visual" do
      [{:custom, module, opts}] =
        Layers.fetch_layers!(layers: [custom: {WxMVU.Visual.Line, width: 3.0}])

      assert module == WxMVU.Visual.Line
      assert opts[:width] == 3.0
    end

    test "the same type may appear twice under different names" do
      layers = Layers.fetch_layers!(layers: [trace_a: :line, trace_b: :line])

      assert Enum.map(layers, &elem(&1, 1)) == [WxMVU.Visual.Line, WxMVU.Visual.Line]
    end

    test "duplicate names are refused" do
      # Silently keeping the last would make one layer's data vanish into a
      # layer that is never drawn.
      assert_raise ArgumentError, ~r/duplicate layer names: \[:trace\]/, fn ->
        Layers.fetch_layers!(layers: [trace: :line, trace: :grid])
      end
    end

    test "an empty stack is refused" do
      assert_raise ArgumentError, ~r/draws nothing/, fn -> Layers.fetch_layers!(layers: []) end
    end

    test "a missing :layers says what is expected" do
      assert_raise ArgumentError, ~r/:layers is required/, fn -> Layers.fetch_layers!([]) end
    end

    test "an unknown visual type reports itself" do
      assert_raise ArgumentError, ~r/unknown visual :sparkle/, fn ->
        Layers.fetch_layers!(layers: [top: :sparkle])
      end
    end

    test "a nonsense declaration says what a layer looks like" do
      assert_raise ArgumentError, ~r/must be a visual type or \{type, opts\}/, fn ->
        Layers.fetch_layers!(layers: [top: "line"])
      end
    end
  end

  describe "resolve/1" do
    test ":layers is a built-in visual like any other" do
      assert WxMVU.Visual.resolve(:layers) == WxMVU.Visual.Layers
    end
  end
end
