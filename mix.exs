defmodule HawthorneStrainer.MixProject do
  use Mix.Project

  def project do
    [
      app: :hawthorne_strainer,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {HawthorneStrainer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.5", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:phoenix_pubsub, "~> 2.2"}
    ]
  end
end
