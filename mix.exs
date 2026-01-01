defmodule Ledger.MixProject do
  use Mix.Project

  def project do
    [
      app: :ledger,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: dialyzer(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Ledger.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Dialyzer configuration
  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  def deps do
    [
      {:tigerbeetlex, "~> 0.16.66"},
      # Development/test only
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:ex_machina, "~> 2.8", only: :test, runtime: false}
    ]
  end
end
