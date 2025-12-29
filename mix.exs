defmodule ChzEx.MixProject do
  use Mix.Project

  @version "0.1.3"
  @source_url "https://github.com/North-Shore-AI/chz_ex"

  def project do
    [
      app: :chz_ex,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "ChzEx",
      description: "Configuration management with CLI parsing for Elixir",
      source_url: @source_url,
      docs: docs(),
      package: package(),

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [
          :error_handling,
          :underspecs,
          :unknown,
          :unmatched_returns
        ]
      ],

      # Test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ChzEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.11"},

      # Dev/Test
      {:stream_data, "~> 0.6", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.all": ["quality", "test --cover"]
    ]
  end

  defp docs do
    [
      main: "ChzEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/chz_ex.svg",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/guides/getting_started.md",
        "docs/guides/cli_parsing.md",
        "docs/guides/polymorphism.md",
        "docs/guides/validation.md",
        "docs/guides/type_system.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          ChzEx,
          ChzEx.Schema,
          ChzEx.Field,
          ChzEx.Blueprint
        ],
        Parsing: [
          ChzEx.Parser,
          ChzEx.ArgumentMap,
          ChzEx.Wildcard
        ],
        Construction: [
          ChzEx.Lazy,
          ChzEx.Factory,
          ChzEx.Factory.Standard,
          ChzEx.Registry
        ],
        Validation: [
          ChzEx.Validator,
          ChzEx.Munger,
          ChzEx.Cast
        ],
        Types: [
          ChzEx.Blueprint.Castable,
          ChzEx.Blueprint.Reference,
          ChzEx.Blueprint.Computed,
          ChzEx.Error
        ]
      ]
    ]
  end

  defp package do
    [
      maintainers: ["North Shore AI"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets)
    ]
  end
end
