defmodule Rbtz.CoverModule.MixProject do
  use Mix.Project

  @name "rbtz_cover_module"
  @description "Custom Mix test coverage tool used in Tiny Robots projects. A drop-in fork of Elixir's Mix.Tasks.Test.Coverage with quieter HTML output."
  @version "0.1.0"
  @source_url "https://github.com/tinyrbtz/cover_module"

  def project do
    [
      app: :rbtz_cover_module,
      name: @name,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      test_coverage: [
        tool: Rbtz.CoverModule,
        summary: [threshold: 100],
        ignore_modules: [Rbtz.CoverModule]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [
        verify: :test
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description, do: @description

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README* LICENSE* CHANGELOG*)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      cspell: [
        "cmd --shell FORCE_COLOR=1 npx cspell lint --unique --relative --no-progress --dot --gitignore --color ."
      ],
      verify: [
        # Order from fastest to slowest
        "compile --force --warnings-as-errors",
        "format --check-formatted",
        "cspell",
        "test --color --cover --raise --warnings-as-errors",
        # performing this at the end so that warnings and todos are obvious
        "credo"
      ]
    ]
  end
end
