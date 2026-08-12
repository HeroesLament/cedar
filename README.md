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

## Shaders

Canvases do not hand-write GLSL. wx_mvu ships a small library of shaders written
in Rust, compiled ahead of time to GLSL 410 and committed under `priv/shaders`:

```
shaders/<name>/src/lib.rs  ->  SPIR-V  ->  GLSL 410  ->  priv/shaders/*.{vert,frag}
```

**Consumers need no Rust toolchain.** The generated GLSL ships in the package;
Rust, the pinned nightly, `cargo-gpu` and `naga` are maintainer tools only, and
none of them appears in your dependency graph.

Shipped today: `image` (data texture through a colormap — waterfalls,
spectrograms, constellations), `line` (polylines expanded to quads, because
`glLineWidth` above 1.0 is unreliable in a 4.1 core profile), `grid` (analytic
antialiased gridlines) and `mesh` (lit geometry).

Shaders are declared rather than wired by hand:

```elixir
defmodule MyCanvas.Shader do
  use WxMVU.GLCanvas.Draw.Program,
    source: {:priv, :wx_mvu, "shaders/image"},
    blocks: [
      per_frame: [
        name: "Uniforms",
        binding: 0,
        fields: [row_offset: :f32, domain_min: :f32, domain_max: :f32]
      ]
    ],
    samplers: [u_data: 0, u_colormap: 1],
    vertex_layout: [a_position: {:f32, 2}, a_texcoord: {:f32, 2}]
end
```

From that declaration wx_mvu derives the std140 packing, the vertex stride and
attribute offsets, and the uniform block plumbing — and validates all of it at
load, including a cross-check of the computed block size against the driver's
own `GL_UNIFORM_BLOCK_DATA_SIZE`. A mismatch raises with a legible message
rather than rendering a black screen.

See `shaders/README.md` for the build commands, how to add a shader, and the
OpenGL 4.1 constraints the shader source has to respect.

---

## Installation

Add `wx_mvu` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wx_mvu, "~> 0.1.0"}
  ]
end
