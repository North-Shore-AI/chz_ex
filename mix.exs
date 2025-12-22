defmodule ChzEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/chz_ex"

  def project do
    [
      app: :chz_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "ChzEx",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Elixir port of OpenAI's chz library - a powerful configuration management system
    for building composable, type-safe command-line interfaces with hierarchical
    configuration, environment variable support, and flexible argument parsing.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "ChzEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/chz_ex.svg",
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp package do
    [
      name: "chz_ex",
      description: description(),
      files: ~w(lib mix.exs README.md LICENSE assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "OpenAI chz (original)" => "https://github.com/openai/chz"
      },
      maintainers: ["North-Shore-AI"]
    ]
  end
end
