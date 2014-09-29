defmodule PlugDrawer.Mixfile do
  use Mix.Project

  def project do
    [app: :plug_drawer,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  def application do
    [applications: [:ssl, :ranch, :cowboy, :plug, :sock_drawer]]
  end

  defp deps do
    [{:plug, "~> 0.7.0 or ~> 0.8.0"}, {:cowboy, "1.0.0"}, {:ranch, "~> 1.0.0"},
      {:sock_drawer,
        [git: "https://github.com/fishcakez/sock_drawer.git", tag: "v0.1.0"]}]
  end
end
