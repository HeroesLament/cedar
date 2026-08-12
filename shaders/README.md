# wx_mvu shader workspace

Source of truth for every shader wx_mvu ships. **No hand-written GLSL.**

```
src/lib.rs  --[cargo-gpu / spirv-unknown-vulkan1.1]-->  *.spv
            --[naga --profile core410]-->  priv/shaders/*.{vert,frag}   (committed)
```

Consumers of wx_mvu never build any of this. They get the committed GLSL from
the Hex package, which is why `priv` is on the `files:` allowlist in `mix.exs`.

## Building

    cargo gpu install          # fetches the pinned nightly + codegen backend
    cargo gpu build -o ./out   # -> out/*.spv
    naga out/image.spv ../priv/shaders/image.frag --profile core410

`cargo-gpu` manages the nightly toolchain and keeps it isolated, so nothing
here affects `native/` or any stable Rust in the tree.

## Target constraints — GL 4.1

macOS caps OpenGL at 4.1 and Apple froze the driver in 2018, so 4.1 is the
floor *and* the ceiling on every platform. rust-gpu will happily let you write
things with no 4.1 equivalent; naga will then fail, or worse, emit GLSL that
Apple's compiler rejects at the user's runtime.

Stay inside this subset:

- **Uniform blocks only.** No push constants — GL 4.1 has no equivalent.
- **Descriptor set 0 only.** GL has no descriptor sets; naga flattens them.
- **No storage buffers, no runtime-sized arrays.** Those need SSBOs (GL 4.3+).
- **No compute, no subgroup ops, no image atomics.**
- **No `layout(binding = ...)` semantics.** That qualifier is GL 4.2; block and
  sampler bindings are resolved at runtime by `WxMVU.GLCanvas.Draw.Program`.

## Uniform blocks

Field order is significant. std140 offsets are positional, and the Elixir side
mirrors the field list in `Program`'s `blocks:` declaration. Reordering fields
here without reordering them there produces silently wrong rendering — which is
why `Program.load/1` cross-checks the computed block size against the driver's
`GL_UNIFORM_BLOCK_DATA_SIZE` on every startup.

Watch `vec3`: it is 12 bytes but aligns to 16. `mat3` is 48 bytes, not 36.

## Testing

Shader crates are `no_std` only under `target_arch = "spirv"`, so they also
build for the host. Pure functions can and should be unit tested:

    cargo test

That is the main reason to write shaders in Rust rather than GLSL — the math is
testable without a GPU.

## Verifying output

Generating GLSL is not the acceptance criterion; linking on Apple's driver is.
Apple's GLSL compiler is the strictest of the three major implementations and
its bugs will never be fixed, so GLSL that works on Mesa or NVIDIA can still
fail there. Regenerated artifacts must be verified on macOS before committing.
