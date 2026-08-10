defmodule WxMVU.MixProject do
  use Mix.Project

  def project do
    [
      app: :wx_mvu,
      version: "0.1.0",
      elixir: "~> 1.19",
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
      files: ~w(lib priv mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/HeroesLament/wx_mvu"
      }
    ]
  end
end
