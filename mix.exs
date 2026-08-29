defmodule ElixirBaseline.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_baseline,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:eex, :logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
      {:nimble_options, "~> 1.1"}
    ]
  end
end
