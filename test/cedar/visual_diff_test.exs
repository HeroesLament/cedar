defmodule Cedar.VisualDiffTest do
  @moduledoc """
  The declarative half of the visuals layer.

  These are pure — no GL context — and they cover the property that makes a
  visual worth declaring rather than constructing: that a change to the model
  becomes a minimal update rather than a teardown.
  """

  use ExUnit.Case, async: true

  alias Cedar.Diff

  defp waterfall(opts) do
    {:ensure_visual, :waterfall, :image, :root, opts}
  end

  @base [grid: {512, 256}, domain: {-100.0, 0.0}, colormap: :viridis]

  describe "creating" do
    test "a new visual is created" do
      intents = [waterfall(@base)]

      assert Diff.compute([], intents) == intents
    end

    test "an unchanged declaration produces no work" do
      intents = [waterfall(@base)]

      assert Diff.compute(intents, intents) == []
    end
  end

  describe "updating" do
    test "a changed domain becomes an update, not a recreate" do
      # This is the whole point. Dragging a dB floor slider must not tear down
      # and rebuild the texture holding the waterfall's history.
      old = [waterfall(@base)]
      new = [waterfall(Keyword.put(@base, :domain, {-80.0, 0.0}))]

      assert [{:update_visual, :waterfall, :image, opts}] = Diff.compute(old, new)
      assert Keyword.get(opts, :domain) == {-80.0, 0.0}

      refute Enum.any?(Diff.compute(old, new), &match?({:destroy_visual, _}, &1))
    end

    test "a changed colormap becomes an update" do
      old = [waterfall(@base)]
      new = [waterfall(Keyword.put(@base, :colormap, :plasma))]

      assert [{:update_visual, :waterfall, :image, opts}] = Diff.compute(old, new)
      assert Keyword.get(opts, :colormap) == :plasma
    end

    test "the update carries the whole declaration, not just the delta" do
      # The visual decides what to do with a change, and it needs the full
      # picture to decide - a changed grid means something different depending
      # on what else changed with it.
      old = [waterfall(@base)]
      new = [waterfall(Keyword.put(@base, :domain, {-50.0, 0.0}))]

      assert [{:update_visual, _, _, opts}] = Diff.compute(old, new)
      assert Keyword.get(opts, :grid) == {512, 256}
      assert Keyword.get(opts, :colormap) == :viridis
    end
  end

  describe "identity" do
    test "a visual is identified by its id, independent of type or options" do
      assert Diff.intent_id(waterfall(@base)) == {:visual, :waterfall}

      assert Diff.intent_id({:ensure_visual, :waterfall, :custom, :other, []}) ==
               {:visual, :waterfall}
    end

    test "visuals are diffable, unlike one-shot intents" do
      assert Diff.diffable?(waterfall(@base))
    end
  end

  describe "destroying" do
    test "a removed visual is destroyed" do
      assert Diff.compute([waterfall(@base)], []) == [{:destroy_visual, :waterfall}]
    end

    test "a visual is destroyed before its parent panel" do
      old = [
        {:ensure_panel, :root, :main, []},
        waterfall(@base)
      ]

      destroys = Diff.compute(old, [])

      visual_at = Enum.find_index(destroys, &match?({:destroy_visual, :waterfall}, &1))
      panel_at = Enum.find_index(destroys, &match?({:destroy_panel, :root}, &1))

      assert visual_at < panel_at,
             "destroying the panel first would take the GL canvas with it"
    end
  end

  describe "coexisting with canvases" do
    test "a visual and a hand-written canvas do not collide" do
      intents = [
        waterfall(@base),
        {:ensure_gl_canvas, :scope, :root, module: SomeCanvas}
      ]

      assert Diff.compute([], intents) == intents

      assert Diff.intent_id(waterfall(@base)) !=
               Diff.intent_id({:ensure_gl_canvas, :waterfall, :root, []})
    end
  end
end
