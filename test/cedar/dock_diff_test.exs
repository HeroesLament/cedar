defmodule Cedar.DockDiffTest do
  @moduledoc """
  What the differ does with dock intents, which is where docking is decided.

  A scene's `view/1` does not reach the renderer directly: `Cedar.Diff` decides
  what changed and emits only that. An intent the differ does not recognise is
  silently never applied — the scene declares a dock host on every frame, the
  differ classifies it as neither creatable nor destroyable, and nothing at all
  happens, with no error anywhere. That is the failure this file exists to
  catch, and it is exactly how docking failed the first time it was run.
  """

  use ExUnit.Case, async: true

  alias Cedar.Diff

  defp host, do: {:ensure_dock_host, :dock, :root, []}
  defp pane(id, opts \\ []), do: {:ensure_dock_pane, id, :dock, opts}

  describe "creation" do
    test "a host and its panes are created" do
      intents = [host(), pane(:viewport, dock: :centre), pane(:tools, dock: :right)]

      assert Diff.compute([], intents) == intents
    end

    test "the host comes before the panes it holds" do
      # Declaration order, preserved: a pane whose host does not exist yet is
      # dropped by the renderer with a debug line, which on a first frame means
      # an application that comes up with no panels and no error.
      intents = [host(), pane(:tools)]

      assert [{:ensure_dock_host, :dock, _, _}, {:ensure_dock_pane, :tools, _, _}] =
               Diff.compute([], intents)
    end
  end

  describe "steady state" do
    test "an unchanged declaration produces nothing" do
      intents = [host(), pane(:tools, dock: :right, size: {260, 500})]

      assert Diff.compute(intents, intents) == []
    end

    test "changed options do NOT move a pane that is already there" do
      # `dock:` and `size:` are where a pane goes the first time. By the second
      # frame the arrangement belongs to whoever is using the program, and a
      # scene whose options happened to change must not yank a pane out of the
      # group the user dropped it into.
      old = [host(), pane(:tools, dock: :right, size: {260, 500})]
      new = [host(), pane(:tools, dock: :left, size: {400, 500})]

      assert Diff.compute(old, new) == []
    end
  end

  describe "destruction" do
    test "a pane that stops being declared is destroyed" do
      old = [host(), pane(:tools)]
      new = [host()]

      assert Diff.compute(old, new) == [{:destroy_dock_pane, :tools}]
    end

    test "panes go before their host, and the host before its window" do
      # wxAuiManager must be uninitialised while the window it manages still
      # exists. The other order is an assertion failure inside wxWidgets, at
      # exit, with no Elixir stack trace to say which window caused it.
      old = [
        {:ensure_window, :main, []},
        {:ensure_panel, :root, :main, []},
        host(),
        pane(:tools)
      ]

      assert [
               {:destroy_dock_pane, :tools},
               {:destroy_panel, :root},
               {:destroy_dock_host, :dock},
               {:destroy_window, :main}
             ] = Diff.compute(old, [])
    end
  end

  describe "commands" do
    test "showing a pane and loading a layout are actions, not declarations" do
      # Non-diffable, so they survive a render in which nothing else changed —
      # and are re-applied on every render if a scene returns them from view/1,
      # which for `:load_dock_layout` is a loop that undoes every drag the user
      # makes. Both are meant for Cedar.Renderer.render/1.
      show = {:update_dock_pane, :tools, shown: true}
      load = {:load_dock_layout, :dock, "layout2|"}

      refute Diff.diffable?(show)
      refute Diff.diffable?(load)

      assert Diff.compute([host()], [host(), show, load]) == [show, load]
    end
  end
end
