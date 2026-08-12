# Shader manifest for `mix wx_mvu.shaders.build`.
#
# Two things live here: the toolchain pin, and the naming contract between the
# Rust source and the Elixir runtime.
#
# ## Toolchain
#
# rust-gpu ships alphas years apart and its own README says to build from the
# `main` branch, so there is no useful semver to depend on - the pin is a git
# revision. Bumping it is a deliberate, tested step: regenerate, run
# `mix wx_mvu.shaders.test`, then `mix run scripts/verify_shaders.exs` on macOS,
# then review the artifact diff. It is not something `cargo update` should do
# to you, which is why shaders/Cargo.lock is committed.
#
# ## Naming
#
# naga discards every name from the Rust and substitutes its own counters, so
# the build rewrites them back to what is declared here. These names must match
# the `blocks:` and `samplers:` declarations in whichever
# `WxMVU.GLCanvas.Draw.Program` module loads the shader.
#
# A mismatch in field *count* fails the build. A mismatch in field *order* is
# caught at load time by the driver's GL_UNIFORM_BLOCK_DATA_SIZE cross-check
# only when it changes the block size - so keep this list in the same order as
# the Rust struct.
#
# Sampler bindings: GLSL 410 merges each texture/sampler pair into a single
# `sampler2D`, so only the texture's binding survives. The separate sampler
# bindings declared in Rust (2 and 4 for :image) never appear in the output.

%{
  rust_gpu: %{
    source: "https://github.com/Rust-GPU/rust-gpu",
    rev: "7cb31ae4f9fb069f6c539fdcdfd68b8b6e77e85f",
    # Set by that revision's rust-toolchain.toml. cargo-gpu installs and
    # isolates it; nothing here touches the stable toolchain used by native/.
    toolchain: "nightly-2026-05-22"
  },

  # Vulkan rather than the spirv-unknown-opengl4.x targets: rust-gpu rates
  # OpenGL support "present in the codebase but not built or tested", while
  # Vulkan is primary. Since the SPIR-V is transpiled to GLSL text and never
  # reaches a driver, staying on the tested target and letting naga lower is
  # the safer route.
  target: "spirv-unknown-vulkan1.1",
  profile: "core410",

  shaders: [
    %{
      name: "image",
      crate: "image",
      entry_points: [vert: "main_vs", frag: "main_fs"],
      block: %{
        name: "Uniforms",
        fields: [:row_offset, :domain_min, :domain_max]
      },
      samplers: %{
        1 => "u_data",
        3 => "u_colormap"
      }
    }
  ]
}
