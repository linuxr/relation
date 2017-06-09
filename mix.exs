defmodule Relation.Mixfile do
  use Mix.Project

  def project do
    [app: :relation,
     version: "0.1.6",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "common relation operations for Relational database",
     package: package(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [mod: {Relation, []},
     applications: [:logger, :phoenix_ecto]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:phoenix_ecto, "~> 3.0"},
     {:phoenix, "~> 1.2"},
     {:ex_doc, "~> 0.14", only: :dev, runtime: false}]
  end

  defp package do
    [
      maintainers: [" wangyubin ", " chenminghua "],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/linuxr/relation"}
    ]
  end
end
