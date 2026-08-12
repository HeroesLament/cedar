defmodule WxMVU.MixProject do
  use Mix.Project

  def project do
    [
      app: :wx_mvu,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :wx],
      mod: {WxMVU.Application, []}
    ]
  end

  # test/support carries WxMVU.GLCase, the shared OpenGL context for the :gl
  # tagged tests. Only compiled in the test env so it never ships.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:wx_ex, "~> 0.5.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    "MVU-based wxWidgets GUIs with integrated OpenGL rendering."
  end

  defp package do
    [
      # `priv` carries committed shader artifacts. It must stay on this list:
      # `files` is an allowlist, and omitting it would ship a package whose
      # shaders are missing at the consumer's runtime rather than at build time.
      files: ~w(lib priv mix.exs README.md LICENSE fonts/dejavu/LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/HeroesLament/wx_mvu"
      }
    ]
  end
end
