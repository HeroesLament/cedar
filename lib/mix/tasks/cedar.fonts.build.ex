defmodule Mix.Tasks.Cedar.Fonts.Build do
  @shortdoc "Bakes SDF font atlases into priv/fonts"

  @moduledoc """
  Bakes the fonts declared in `fonts/fonts.exs` into `priv/fonts/`.

      mix cedar.fonts.build
      mix cedar.fonts.build --check

  A maintainer task. Its output is committed, and **consumers never run it** —
  they read `priv/fonts/*.font` and need no Rust, no font file and no image
  library. That is the same boundary `mix cedar.shaders.build` draws.

  ## What it produces

  One file per font: `priv/fonts/<name>.font`, a compressed Erlang term
  containing both the metrics and the atlas bytes.

  A single file rather than the tool's natural pair of JSON plus raw pixels,
  because the alternative costs the runtime a JSON decoder and an image
  decoder, and neither is a dependency worth acquiring to read data this
  project generated itself. `:erlang.term_to_binary/2` with `:compressed` is in
  OTP, understands binaries natively, and takes the 260KB atlas down to
  something a package can carry without comment.

  ## `--check`

  Rebakes into a temporary directory and compares. Non-zero exit means the
  committed artifact no longer matches the manifest and the source font — the
  same drift check the shader build has, and it belongs in CI for the same
  reason: a committed artifact that nobody verifies is a committed artifact
  that is quietly wrong.
  """

  use Mix.Task

  @manifest "fonts/fonts.exs"

  @impl true
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [check: :boolean])
    check? = Keyword.get(opts, :check, false)

    manifest = read_manifest()
    tool = Map.fetch!(manifest, :atlas_tool)

    ensure_cargo!()

    results =
      for font <- Map.fetch!(manifest, :fonts) do
        Mix.shell().info("\n== #{font.name}")
        bake(font, tool, check?)
      end

    if check? do
      case Enum.reject(results, &(&1 == :ok)) do
        [] ->
          Mix.shell().info("\nAll font atlases match the manifest.")

        drifted ->
          Mix.raise("""
          Font atlases are out of date: #{Enum.map_join(drifted, ", ", &elem(&1, 1))}

          Run `mix cedar.fonts.build` and commit the result.
          """)
      end
    else
      Mix.shell().info("\nDone. Now run:")
      Mix.shell().info("  mix test test/cedar/font_test.exs")
      Mix.shell().info("  mix test test/cedar/ --only gl")
    end
  end

  # ==========================================================================

  defp read_manifest do
    unless File.exists?(@manifest) do
      Mix.raise("#{@manifest} not found. Run this from the cedar project root.")
    end

    {manifest, _bindings} = Code.eval_file(@manifest)
    manifest
  end

  defp ensure_cargo! do
    unless System.find_executable("cargo") do
      Mix.raise("""
      cargo not found.

      This is a maintainer task: it needs a stable Rust toolchain to run the
      atlas baker. Consumers of cedar do not, and never will — the baked
      atlas is committed under priv/fonts.
      """)
    end
  end

  defp bake(font, tool, check?) do
    out =
      Path.join(
        System.tmp_dir!(),
        "cedar_atlas_#{font.name}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(out)

    try do
      run_tool!(font, tool, out)

      term = assemble(font, out)
      encoded = :erlang.term_to_binary(term, compressed: 9)

      destination = Path.join("priv/fonts", "#{font.name}.font")

      if check? do
        compare(destination, encoded, font)
      else
        File.mkdir_p!("priv/fonts")
        File.write!(destination, encoded)

        Mix.shell().info(
          "   wrote    #{destination} " <>
            "(#{map_size(term.glyphs)} glyphs, #{byte_size(encoded)} bytes)"
        )

        :ok
      end
    after
      File.rm_rf(out)
    end
  end

  defp run_tool!(font, tool, out) do
    args = [
      "run",
      "--quiet",
      "--release",
      "--manifest-path",
      Path.join(tool, "Cargo.toml"),
      "--",
      "--font",
      font.source,
      "--out",
      out,
      "--name",
      font.name,
      "--size",
      to_string(font.size),
      "--range",
      to_string(font.range),
      "--padding",
      to_string(font.padding),
      "--width",
      to_string(font.width)
    ]

    args = args ++ if font[:extra], do: ["--extra", font.extra], else: []

    unless File.exists?(font.source) do
      Mix.raise("font source #{font.source} not found")
    end

    if font.padding < font.range do
      Mix.raise("""
      #{font.name}: padding (#{font.padding}) is less than range (#{font.range}).

      The distance field extends `range` pixels beyond each glyph's ink. With
      less padding than that it is clipped by the neighbouring cell, and the
      outermost antialiased pixels sample another glyph's field.
      """)
    end

    case System.cmd("cargo", args, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.each(&Mix.shell().info("   atlas    #{&1}"))

      {output, status} ->
        Mix.raise("the atlas tool failed (exit #{status}):\n\n#{output}")
    end
  end

  defp assemble(font, out) do
    atlas = File.read!(Path.join(out, "#{font.name}.r8"))
    metrics = out |> Path.join("#{font.name}.json") |> File.read!() |> JSON.decode!()

    glyphs =
      Map.new(metrics["glyphs"], fn g ->
        {g["codepoint"],
         %{
           x: g["x"],
           y: g["y"],
           w: g["w"],
           h: g["h"],
           left: g["left"] * 1.0,
           top: g["top"] * 1.0,
           advance: g["advance"] * 1.0
         }}
      end)

    kerning =
      Map.new(metrics["kerning"], fn {pair, k} ->
        [a, b] = String.split(pair, ":")
        {{String.to_integer(a), String.to_integer(b)}, k * 1.0}
      end)

    expected = metrics["atlas_width"] * metrics["atlas_height"]

    if byte_size(atlas) != expected do
      Mix.raise(
        "#{font.name}: atlas is #{byte_size(atlas)} bytes, expected " <>
          "#{expected} for #{metrics["atlas_width"]}x#{metrics["atlas_height"]}"
      )
    end

    %{
      version: 1,
      name: metrics["name"],
      size: metrics["size"] * 1.0,
      range: metrics["range"] * 1.0,
      atlas_width: metrics["atlas_width"],
      atlas_height: metrics["atlas_height"],
      ascent: metrics["ascent"] * 1.0,
      descent: metrics["descent"] * 1.0,
      line_height: metrics["line_height"] * 1.0,
      atlas: atlas,
      glyphs: glyphs,
      kerning: kerning
    }
  end

  defp compare(destination, encoded, font) do
    cond do
      not File.exists?(destination) ->
        Mix.shell().error("   MISSING  #{destination}")
        {:drift, font.name}

      File.read!(destination) == encoded ->
        Mix.shell().info("   ok       #{destination}")
        :ok

      true ->
        Mix.shell().error("   DRIFT    #{destination}")
        {:drift, font.name}
    end
  end
end
