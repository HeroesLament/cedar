defmodule Mix.Tasks.WxMvu.Shaders.Build do
  @shortdoc "Builds shaders from Rust and writes committed GLSL 410 into priv/"

  @moduledoc """
  Builds the shader crates in `shaders/` and writes GLSL 410 into `priv/shaders/`.

      mix wx_mvu.shaders.build

  This is a maintainer task. Consumers of wx_mvu never run it - they get the
  committed GLSL from the Hex package and need no Rust toolchain at all.

  ## Pipeline

      shaders/<crate>/src/lib.rs
        -> cargo gpu build --target spirv-unknown-vulkan1.1     (*.spv)
        -> naga --profile core410                               (generated GLSL)
        -> WxMVU.Shaders.Rewriter                               (stable names)
        -> priv/shaders/<name>.{vert,frag}                      (committed)

  The rewrite step is not cosmetic. naga names the uniform block from its own
  type counter - `type_6_block_0Fragment` - and that name is the key passed to
  `glGetUniformBlockIndex` at runtime. Committing it as-is would couple the
  runtime to a number that moves whenever a struct is added or naga is bumped.

  ## Requirements

      cargo install --git https://github.com/Rust-GPU/rust-gpu cargo-gpu
      cargo install naga-cli

  `cargo-gpu` manages its own pinned nightly in an isolated cache, so nothing
  here touches the stable toolchain used by `native/`.

  ## Checking for drift

      mix wx_mvu.shaders.build --check

  Regenerates without writing and fails if the result differs from what is
  committed. Since the toolchain is pinned to an exact revision, regeneration is
  byte-reproducible, so any difference means the committed GLSL no longer
  matches the Rust it claims to come from - someone edited a shader and forgot
  to rebuild, or edited `priv/shaders` by hand.

  Suitable for CI on a machine that has the toolchain. It is not a substitute
  for `verify_shaders.exs`, which checks something different: that the artifacts
  actually compile on a real driver.

  ## After building

  Run `mix run scripts/verify_shaders.exs` to confirm the output links on the
  local driver before committing. On macOS that driver is Apple's frozen 4.1
  implementation, the strictest consumer of the three major platforms.
  """

  use Mix.Task

  alias WxMVU.Shaders.Rewriter


  @impl Mix.Task
  def run(args) do
    check? = "--check" in args
    workspace = Path.join(File.cwd!(), "shaders")
    out_dir = Path.join(workspace, "out")
    priv_dir = Path.join(File.cwd!(), "priv/shaders")

    unless File.dir?(workspace) do
      Mix.raise("no shaders/ workspace found at #{workspace}")
    end

    require_executable!("cargo-gpu")
    require_executable!("naga")

    File.mkdir_p!(priv_dir)

    manifest = read_manifest(workspace)

    Mix.shell().info(
      "rust-gpu #{String.slice(manifest.rust_gpu.rev, 0, 8)} " <>
        "on #{manifest.rust_gpu.toolchain}, target #{manifest.target}"
    )

    if check?, do: Mix.shell().info("checking committed artifacts, writing nothing")

    Enum.each(
      manifest.shaders,
      &build_shader(&1, manifest, workspace, out_dir, priv_dir, check?)
    )

    case Process.get(:drifted, []) do
      [] ->
        :ok

      drifted ->
        Mix.raise("""
        committed GLSL does not match what the Rust currently produces:

        #{Enum.map_join(drifted, "\n", &"  #{&1}")}

        Run `mix wx_mvu.shaders.build` and commit the result.
        """)
    end

    if check?, do: Mix.shell().info("\nCommitted artifacts are up to date.")

    unless check?,
      do:
        Mix.shell().info(
          "\nDone. Now run:\n" <>
              "  mix wx_mvu.shaders.test              # host-side shader math\n" <>
            "  mix run scripts/verify_shaders.exs   # links on the local driver\n" <>
            "  mix run scripts/golden_image.exs     # renders correctly"
        )
  end

  # ==========================================================================

  defp read_manifest(workspace) do
    path = Path.join(workspace, "shaders.exs")

    unless File.exists?(path) do
      Mix.raise("no shader manifest at #{path}")
    end

    {manifest, _bindings} = Code.eval_file(path)
    manifest
  end

  defp build_shader(shader, manifest, workspace, out_dir, priv_dir, check?) do
    Mix.shell().info("\n== #{shader.name}")

    # --spirv-builder-source/-version pin the codegen backend to the same
    # revision the shader crate depends on. Without them cargo-gpu resolves
    # whatever `main` happens to be, which can disagree with Cargo.lock.
    cmd!(
      "cargo-gpu",
      [
        "build",
        "--shader-crate",
        "./#{shader.crate}",
        "--target",
        manifest.target,
        "--spirv-metadata",
        "name-variables",
        "--spirv-builder-source",
        manifest.rust_gpu.source,
        "--spirv-builder-version",
        manifest.rust_gpu.rev,
        "-o",
        "./out/#{shader.name}"
      ],
      workspace
    )

    shader_out = Path.join(out_dir, shader.name)

    spv =
      case Path.wildcard(Path.join(shader_out, "*.spv")) do
        [single] -> single
        [] -> Mix.raise("cargo-gpu produced no .spv in #{shader_out}")
        many -> Mix.raise("expected one .spv, found #{length(many)}: #{inspect(many)}")
      end

    Mix.shell().info("   spirv    #{Path.relative_to(spv, File.cwd!())}")

    sources =
      Map.new(shader.entry_points, fn {stage, entry_point} ->
        target = Path.join(shader_out, "#{shader.name}.#{stage}")
        cmd!(
          "naga",
          ["--entry-point", entry_point, "--profile", manifest.profile, spv, target],
          workspace
        )
        {stage, File.read!(target)}
      end)

    spec = %{block: shader.block, samplers: Map.get(shader, :samplers, %{})}

    case Rewriter.rewrite_pair(sources.vert, sources.frag, spec) do
      {:ok, rewritten, mapping} ->
        report(mapping)

        Enum.each(rewritten, fn {stage, glsl} ->
          path = Path.join(priv_dir, "#{shader.name}.#{stage}")
          relative = Path.relative_to(path, File.cwd!())

          if check? do
            case File.read(path) do
              {:ok, ^glsl} ->
                Mix.shell().info("   ok       #{relative}")

              {:ok, _different} ->
                Mix.shell().error("   DRIFT    #{relative}")
                Process.put(:drifted, [relative | Process.get(:drifted, [])])

              {:error, :enoent} ->
                Mix.shell().error("   MISSING  #{relative}")
                Process.put(:drifted, [relative | Process.get(:drifted, [])])
            end
          else
            File.write!(path, glsl)
            Mix.shell().info("   wrote    #{relative}")
          end
        end)

      {:error, reason} ->
        Mix.raise("""
        rewriting #{shader.name} failed:

          #{reason}

        The generated GLSL no longer matches the declaration in
        shaders/shaders.exs. Either the Rust source changed without the
        manifest being updated, or naga's output shape has changed.
        """)
    end
  end

  defp report(mapping) do
    {block_from, block_to} = mapping.block
    Mix.shell().info("   block    #{block_from} -> #{block_to}")

    Enum.each(mapping.samplers, fn {from, to} ->
      Mix.shell().info("   sampler  #{from} -> #{to}")
    end)

    fields = Enum.map_join(mapping.fields, ", ", fn {_from, to} -> to end)
    Mix.shell().info("   fields   #{fields}")
  end

  defp cmd!(executable, args, cd) do
    case System.cmd(executable, args, cd: cd, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Mix.raise("#{executable} exited #{status}:\n\n#{output}")
    end
  end

  defp require_executable!(name) do
    unless System.find_executable(name) do
      Mix.raise("""
      #{name} not found on PATH.

          cargo install --git https://github.com/Rust-GPU/rust-gpu cargo-gpu
          cargo install naga-cli
      """)
    end
  end
end
