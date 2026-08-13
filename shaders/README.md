# cedar shader workspace

Source of truth for every shader cedar ships. **No hand-written GLSL.**

```
core/src/lib.rs      shader maths, no spirv-std, tests on stable
<name>/src/lib.rs    entry points and bindings, needs the pinned nightly
        │  cargo-gpu --target spirv-unknown-vulkan1.1
        ▼
     *.spv
        │  naga --profile core410
        ▼
   generated GLSL
        │  Cedar.Shaders.Rewriter          (naga's names -> declared names)
        ▼
priv/shaders/*.{vert,frag}                 committed, shipped in the package
```

Consumers of cedar build none of this. They get the committed GLSL from Hex and
need no Rust toolchain at all, which is why `priv` is on the `files:` allowlist
in `mix.exs`.

## Commands

    mix cedar.shaders.build           # regenerate priv/shaders
    mix cedar.shaders.build --check   # fail if committed artifacts have drifted
    mix cedar.shaders.test            # host-side maths, stable then nightly
    mix run scripts/verify_shaders.exs # compile and link on the local driver
    mix test --only gl                 # render and check pixels

One-time setup:

    cargo install --git https://github.com/Rust-GPU/rust-gpu cargo-gpu
    cargo install naga-cli

`cargo-gpu` installs and isolates the pinned nightly itself, so nothing here
touches the stable toolchain used by `native/`.

## Adding a shader

1. `cargo new --lib <name>` under `shaders/`, copying an existing `Cargo.toml`.
   Add it to the workspace `members`.
2. Put pure functions in `core`, not the shader crate. They test on stable and
   the shader crate does not.
3. Add an entry to `shaders.exs` naming the uniform block, its fields **in
   declaration order**, and any sampler bindings.
4. `mix cedar.shaders.build`, then `verify_shaders`, then a `:gl` test.

Adding the declaration in three places — Rust struct, `shaders.exs`, and the
`Program` module — is deliberate. Each checks the others: a field-count mismatch
fails the build, and a layout mismatch fails at load against the driver's
`GL_UNIFORM_BLOCK_DATA_SIZE`.

## Target constraints — GL 4.1

macOS caps OpenGL at 4.1 and Apple froze the driver in 2018, so 4.1 is the floor
*and* the ceiling on every platform. rust-gpu will happily let you write things
with no 4.1 equivalent; naga then fails, or worse, emits GLSL that Apple's
compiler rejects at a user's runtime.

- **Uniform blocks only.** No push constants — GL 4.1 has no equivalent.
- **Descriptor set 0 only.** GL has no descriptor sets; naga flattens them.
- **No storage buffers or runtime-sized arrays.** Those need SSBOs (GL 4.3+).
- **No compute, no subgroup ops, no image atomics.**
- **No `layout(binding = ...)`.** That qualifier is GL 4.2; block and sampler
  bindings are resolved at runtime by `Cedar.GLCanvas.Draw.Program`.

## Known constraints, found the hard way

Each of these cost real time to diagnose. None is obvious from the error.

**`glam::Mat3` cannot go in a uniform block. Use `Mat3A`.**
`Mat3` is three tightly packed `Vec3`, giving column offsets 0/12/24; std140
requires a 16-byte column stride. rust-gpu emits glam's CPU layout faithfully, so
SPIR-V validation rejects it with *"improperly straddling vector at offset 76"*.
`Mat3A` is built on `Vec3A` and lays out as 3×16 = 48, which is what std140
wants. The same applies to any `Vec3` you need tightly controlled.

**`glam`'s `normalize_or_zero` cannot be used at all.**
It guards with `is_finite()`, which compiles to a comparison against an infinity
constant, and naga refuses to translate a module containing one: *"Float literal
is infinite"*. Use `cedar_shader_core::normalize2` / `normalize3`, which guard
by comparing a squared length against zero. Anything else reaching for
`is_finite` will hit the same wall.

**Beware overflow before you beware infinity.**
Squaring a coordinate above ~1.8e19 overflows f32, and Newton–Raphson on
infinity returns NaN. `normalize2`/`normalize3` scale by the largest component
before squaring, which bounds every intermediate — and does so without an
`is_finite` check, which would reintroduce the naga problem.

**naga names a uniform block per stage.**
The same block is `..._block_0Fragment` in one file and `..._block_0Vertex` in
the other, with instances suffixed `_fs` and `_vs`. GLSL links blocks *by name*,
so renaming only one leaves two different blocks and one stage silently
receiving no uniform data. `Rewriter.rewrite_pair/3` derives per stage for this
reason.

**GLSL 410 merges each texture/sampler pair.**
Only the texture's binding survives into the output. If you declare a texture at
binding 1 and its sampler at 2, only 1 appears — so `shaders.exs` lists 1 and 3
for `:image`, not 1 through 4.

**Analytic lines need box-filter coverage, not a linear ramp.**
Gridlines land on integer coordinates, which fall on pixel *boundaries*, so every
sample point sits half a pixel away. A ramp reaching zero at half-thickness
evaluates to exactly zero on both neighbours and a 1px line disappears entirely.
See `grid_line_alpha`.

## Testing

Shader crates are `no_std` only under `target_arch = "spirv"`, so they also build
for the host and their pure functions can be unit tested without a GPU:

    mix cedar.shaders.test

This needs the **pinned nightly**, not stable: `spirv-std` uses unstable features
(`cfg_select!`), so even a host build of a crate depending on it fails on stable
with E0658. `core` has no `spirv-std` dependency and is therefore run on stable
*first*, specifically so that a `spirv-std` dependency creeping into it fails
loudly there and nowhere else.

## Verifying output

Four layers, none of which subsumes another:

| Layer | Catches | Needs |
|---|---|---|
| `mix cedar.shaders.test` | wrong maths | nothing |
| `mix cedar.shaders.build --check` | artifacts out of sync with source | toolchain |
| `scripts/verify_shaders.exs` | GLSL the driver rejects | a GL context |
| `mix test --only gl` | shaders that link and draw the wrong thing | a GL context |

Generating GLSL is not the acceptance criterion; rendering correct pixels is.
Apple's GLSL compiler is the strictest of the three major implementations and its
bugs will never be fixed, so **regenerated artifacts must be verified on macOS**
before committing. CI on Linux alone will not catch it.

## Toolchain

rust-gpu ships alphas years apart and its own README says to build from `main`,
so the pin is a git revision rather than a semver range. It lives in
`shaders.exs` alongside the naming contract, and `Cargo.lock` is committed as the
record of what produced the artifacts.

Bumping it is a deliberate step: regenerate, run the tests above, and review the
artifact diff. It is not something `cargo update` should do to you.
