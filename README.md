# WxMvu

[![GitHub](https://img.shields.io/badge/github-HeroesLament%2Fwx_mvu-black?logo=github)](https://github.com/HeroesLament/wx_mvu)
[![Hex.pm](https://img.shields.io/hexpm/v/wx_mvu.svg)](https://hex.pm/packages/wx_mvu)
[![Hex Docs](https://img.shields.io/hexpm/docs/wx_mvu.svg)](https://hexdocs.pm/wx_mvu)
[![Build Status](https://github.com/HeroesLament/wx_mvu/actions/workflows/ci.yml/badge.svg)](https://github.com/HeroesLament/wx_mvu/actions)
[![License](https://img.shields.io/hexpm/l/wx_mvu.svg)](https://github.com/HeroesLament/wx_mvu/blob/main/LICENSE)

MVU-based wxWidgets GUIs with integrated OpenGL rendering.

---

## Requirements

* **Erlang/OTP built with wxWidgets.** This is the one thing that trips people
  up. A distribution's Erlang package normally has it; an Erlang built from
  source on a machine without the wxWidgets headers silently does not, and
  `:wx.new()` then fails with `{:load_driver, 'No driver found'}`. Install
  wxWidgets (`brew install wxwidgets`, `apt install libwxgtk3.2-dev`) and
  rebuild Erlang.
* **OpenGL 4.1.** That is the ceiling macOS offers and the target everything
  here is compiled against, so it is the floor elsewhere too.
* **No Rust, and no font tooling.** The shaders and the font atlas are
  compiled ahead of time and committed; see [Shaders](#shaders) and
  [Fonts](#fonts).

Developed against Erlang 28 and Elixir 1.19 on macOS.

## Try it

```sh
git clone https://github.com/HeroesLament/wx_mvu
cd wx_mvu
mix deps.get
mix run examples/chess.exs
```

A chess board you push pieces around by clicking. No rules and no opponent —
the point is that the whole thing is a pure function from a model to a
declaration, with no GLSL, no buffers and no rendering code. See
[`examples/`](examples/).

---

## Overview

WxMvu is a Model–View–Update framework for building native desktop applications
on the BEAM using wxWidgets.

It enforces a strict separation between immutable application state, pure update
logic, and declarative UI structure, while confining all direct wxWidgets calls
to a dedicated renderer process.

In addition to standard widgets, WxMvu provides a managed OpenGL canvas model for
high-throughput, real-time rendering such as scopes, waterfalls, and custom
visualizations. OpenGL canvases own their rendering loop and context, receive
data directly via message passing, and intentionally bypass MVU diffing.

The goal is not to abstract wxWidgets or OpenGL away, but to contain them within
clear ownership and lifecycle boundaries that fit naturally into OTP systems.

---

## Visuals

High-throughput rendering is declared, not wired. A waterfall is a line in
`view/1`:

```elixir
def view(model) do
  [
    {:ensure_window, :main, title: "Spectrum"},
    {:ensure_panel, :root, :main, []},

    {:ensure_visual, :waterfall, :image, :root,
      grid: {512, 256},
      domain: {model.db_floor, 0.0},
      colormap: :viridis,
      advance: :per_datum},

    {:ensure_widget, :floor, :slider, :root, min: -140, max: -20},
    {:layout, :root, {:vbox, [], [:waterfall, :floor]}},
    {:refresh, :main}
  ]
end
```

Sample data bypasses MVU, as it does for canvases:

```elixir
WxMVU.Visual.send_data(:waterfall, {:row, bins})
```

Configuration flows the other way. Dragging that slider changes `model.db_floor`,
the differ sees one visual whose declaration changed, and the runtime issues a
single uniform write — it does not tear down the texture holding the waterfall's
history.

Built-in visuals are named by atom, exactly as widgets are:

| Visual | Draws |
|---|---|
| `:image` | a 2D scalar field through a colormap — waterfalls, spectrograms, constellations, heatmaps |
| `:line` | polylines with a width in pixels — traces, scope sweeps, axis rules |
| `:grid` | analytic antialiased gridlines |
| `:mesh` | lit triangle geometry with a camera — the 3D viewport |
| `:text` | strings from a distance field atlas, crisp at any size |

A 3D viewport is the same shape of declaration, with a camera instead of a
colormap:

```elixir
{:ensure_visual, :viewport, :mesh, :root,
  eye: model.camera.eye,
  target: model.camera.target,
  base_color: {0.8, 0.55, 0.15, 1.0}}
```

```elixir
WxMVU.Visual.send_data(:viewport, {:mesh, WxMVU.Visual.Mesh.box({2.0, 0.4, 0.4})})
```

Orbiting that camera changes two tuples in the model; the differ turns it into
a 144-byte uniform write, and the mesh on the GPU is not touched. `WxMVU.Math`
supplies the matrices — column-major, degrees, right-handed — if you want to
build a transform yourself.

Labels are the same shape again, and need nothing installed:

```elixir
{:ensure_visual, :readout, :text, :root,
  text: "Joint 3: 47.2°",
  size: 14.0,
  origin: {12.0, 12.0}}
```

One atlas serves every size — the glyph is stored as a distance to its outline
rather than as coverage, so a 200pt title and an 8px axis label come from the
same 25 KB file. `WxMVU.Font.measure/3` sizes a control around a string without
drawing it.

Your own visual implements `WxMVU.Visual` and is referenced by module, matching
how `:ensure_gl_canvas` takes one:

```elixir
{:ensure_visual, :radar, :custom, :root,
  module: MyApp.Visuals.PolarRadar, opts: [sweep_rate: 30]}
```

`WxMVU.GLCanvas` remains for cases a visual does not cover — it is what visuals
are built on, and nothing about it has been removed.

## Shaders

Visuals are backed by a small library of shaders written in Rust, compiled ahead
of time to GLSL 410 and committed under `priv/shaders`:

```
shaders/<name>/src/lib.rs  ->  SPIR-V  ->  GLSL 410  ->  priv/shaders/*.{vert,frag}
```

**Consumers need no Rust toolchain.** The generated GLSL ships in the package;
Rust, the pinned nightly, `cargo-gpu` and `naga` are maintainer tools only, and
none of them appears in your dependency graph.

Applications do not write GLSL either. If you are adding a shader to wx_mvu
itself, see `shaders/README.md` for the build commands and the OpenGL 4.1
constraints the source has to respect.

## Fonts

`:text` draws from a signed distance field atlas baked the same way and for the
same reason: a maintainer tool produces it, the result is committed under
`priv/fonts`, and applications need no font file, no rasterizer and no image
decoder. See `fonts/README.md`.

DejaVu Sans ships as the default. Its licence travels with it in the package.

---

## Installation

Add `wx_mvu` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wx_mvu, "~> 0.1.0"}
  ]
end
