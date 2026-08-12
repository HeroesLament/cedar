# Shader manifest for `mix wx_mvu.shaders.build`.
#
# This is the naming contract between the Rust source and the Elixir runtime.
# naga discards every name from the Rust and substitutes its own counters, so
# the build rewrites them back to what is declared here.
#
# These names must match the `blocks:` and `samplers:` declarations in whichever
# `WxMVU.GLCanvas.Draw.Program` module loads the shader. A mismatch in field
# *count* fails the build; a mismatch in field *order* is caught at load time by
# the driver's GL_UNIFORM_BLOCK_DATA_SIZE cross-check only if it changes the
# size, so keep this list in the same order as the Rust struct.
#
# Note on sampler bindings: GLSL 410 merges each texture/sampler pair into one
# `sampler2D`, so only the texture's binding survives into the output. The
# separate sampler bindings declared in Rust (2 and 4 here) never appear.

[
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
