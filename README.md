# WxMvu

[![GitHub](https://img.shields.io/badge/github-HeroesLament%2Fwx_mvu-black?logo=github)](https://github.com/HeroesLament/wx_mvu)
[![Hex.pm](https://img.shields.io/hexpm/v/wx_mvu.svg)](https://hex.pm/packages/wx_mvu)
[![Hex Docs](https://img.shields.io/hexpm/docs/wx_mvu.svg)](https://hexdocs.pm/wx_mvu)
[![Build Status](https://github.com/HeroesLament/wx_mvu/actions/workflows/ci.yml/badge.svg)](https://github.com/HeroesLament/wx_mvu/actions)
[![License](https://img.shields.io/hexpm/l/wx_mvu.svg)](https://github.com/HeroesLament/wx_mvu/blob/main/LICENSE)

MVU-based wxWidgets GUIs with integrated OpenGL rendering.

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

---

## Installation

Add `wx_mvu` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wx_mvu, "~> 0.1.0"}
  ]
end
