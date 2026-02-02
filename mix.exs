defmodule Operator.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/gamedev-company/operator"

  def project do
    [
      app: :operator,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),

      # Hex
      name: "Operator",
      description: "HTN planning and narrative orchestration library for games and simulations",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Operator.Application, []}
    ]
  end

  defp deps do
    [
      # Dev/Test
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/architecture.md",
        "guides/best_practices.md",
        "guides/anti_patterns.md",
        "guides/debugging.md",
        "guides/dsl_reference.md",
        "guides/director.md",
        "guides/getting_started.md",
        "guides/howto.md",
        "guides/testing.md",
        "guides/cheatsheet.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end
end
