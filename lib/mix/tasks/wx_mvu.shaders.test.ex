defmodule Mix.Tasks.WxMvu.Shaders.Test do
  @shortdoc "Runs the shader crates' host-side unit tests"

  @moduledoc """
  Runs `cargo test` for the shader crates, on the pinned nightly toolchain.

      mix wx_mvu.shaders.test

  Shader crates are `no_std` only under `target_arch = "spirv"`, so they also
  build for the host. Pure functions - colormap interpolation, domain mapping,
  ribbon frame math - can therefore be unit tested on the CPU without a GPU,
  a graphics context, or a rendered frame. That is the main practical reason to
  write shaders in Rust rather than GLSL.

  ## Why not plain `cargo test`

  `spirv-std` uses unstable features (`cfg_select!`), so *any* build of a crate
  that depends on it - including a host build - fails on stable with E0658.
  This task selects the toolchain pinned in `shaders/shaders.exs`, which is the
  one cargo-gpu installed.

  If you want shader math testable on stable, move it into a crate with no
  `spirv-std` dependency and have the shader crate call into it.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    workspace = Path.join(File.cwd!(), "shaders")

    unless File.dir?(workspace) do
      Mix.raise("no shaders/ workspace found at #{workspace}")
    end

    manifest_path = Path.join(workspace, "shaders.exs")
    {manifest, _bindings} = Code.eval_file(manifest_path)
    toolchain = manifest.rust_gpu.toolchain

    Mix.shell().info("Running shader tests on #{toolchain}\n")

    case System.cmd("cargo", ["+#{toolchain}", "test" | args],
           cd: workspace,
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_stream, 0} ->
        :ok

      {_stream, status} ->
        Mix.raise("""
        shader tests failed (exit #{status}).

        If the failure is E0658 "use of unstable library feature", the wrong
        toolchain was selected. Check that #{toolchain} is installed:

            rustup toolchain list
        """)
    end
  end
end
