defmodule Mix.Tasks.Cedar.Shaders.Test do
  @shortdoc "Runs the shader crates' host-side unit tests"

  @moduledoc """
  Runs `cargo test` for the shader crates, on the pinned nightly toolchain.

      mix cedar.shaders.test

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
    stable_crates = Map.get(manifest, :stable_crates, [])

    # Stable pass first. These crates hold the shader maths and must not depend
    # on spirv-std; running them on stable is what enforces that, because a
    # spirv-std dependency fails here with E0658 and nowhere else.
    Enum.each(stable_crates, fn crate ->
      Mix.shell().info("== #{crate} (stable)")
      run!(workspace, ["+stable", "test", "-p", crate | args], stable_hint(crate))
    end)

    Mix.shell().info("\n== workspace (#{toolchain})")
    run!(workspace, ["+#{toolchain}", "test", "--workspace" | args], nightly_hint(toolchain))
  end

  defp run!(workspace, args, hint) do
    case System.cmd("cargo", args,
           cd: workspace,
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_stream, 0} -> :ok
      {_stream, status} -> Mix.raise("cargo exited #{status}.\n\n#{hint}")
    end
  end

  defp stable_hint(crate) do
    """
    #{crate} is declared in shaders/shaders.exs as a crate that must build on
    stable Rust. If this failed with E0658 "use of unstable library feature",
    something in its dependency graph now pulls in spirv-std. Move the code
    that needs spirv-std into a shader crate instead.
    """
  end

  defp nightly_hint(toolchain) do
    """
    If this failed with E0658, the wrong toolchain was selected. Check that
    #{toolchain} is installed:

        rustup toolchain list
    """
  end
end
