defmodule ElixirBaseline.Config do
  @moduledoc """
  Reads `.baseline.exs` and resolves each repo's settings.

  Lookup order:

  - repo configuration
  - group configuration
  - "all" group configuration
  - library defaults
  """

  @path ".baseline.exs"
  @defaults [all: [line_length: 80]]

  @doc """
  Returns all configured repos with their settings resolved.
  """
  @spec repos(keyword) :: [map]
  def repos(opts \\ []) do
    opts = Keyword.validate!(opts, path: @path, only: nil)
    only = Keyword.fetch!(opts, :only)
    {config, _} = opts |> Keyword.fetch!(:path) |> Code.eval_file()
    defaults = config[:defaults] || []

    config
    |> Keyword.fetch!(:repos)
    |> filter_repos(only)
    |> Enum.map(fn {name, spec} -> resolve(defaults, name, spec) end)
  end

  defp filter_repos(repos, only) when is_list(only) do
    Enum.filter(repos, fn {name, _} -> to_string(name) in only end)
  end

  defp filter_repos(repos, nil), do: repos

  @doc """
  Returns the `owner/repo` slug of a resolved repo.
  """
  @spec slug(map) :: String.t()
  def slug(%{owner: owner, name: name}), do: "#{owner}/#{name}"

  defp resolve(defaults, name, spec) do
    [@defaults, defaults]
    |> Enum.flat_map(&[&1[:all], &1[spec[:group]]])
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], &Keyword.merge(&2, &1))
    |> Keyword.merge(spec)
    |> Map.new()
    |> Map.put(:name, name)
  end
end
