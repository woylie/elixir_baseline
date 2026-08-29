defmodule ElixirBaseline.Config do
  @moduledoc """
  Reads `.baseline.override.exs`, or `.baseline.exs` where there is no override,
  and resolves each repo's settings.

  Lookup order:

  - repo configuration
  - group configuration
  - "all" group configuration
  - elixir_baseline's own defaults
  """

  @path ".baseline.exs"
  @override ".baseline.override.exs"
  @defaults [all: [line_length: 80]]

  @settings [
    line_length: [
      type: :pos_integer,
      doc: "Line length for the formatter."
    ]
  ]

  @group_schema NimbleOptions.new!([owner: [type: :string]] ++ @settings)

  @repo_schema NimbleOptions.new!(
                 [
                   owner: [type: :string, doc: "GitHub owner of the repo."],
                   group: [
                     type: :atom,
                     doc:
                       "The group defined under `defaults` this repo belongs to."
                   ]
                 ] ++ @settings
               )

  @doc """
  Returns all configured repos with their settings resolved.
  """
  @spec repos(keyword) :: [map]
  def repos(opts \\ []) do
    opts = Keyword.validate!(opts, path: default_path(), only: nil)
    only = Keyword.fetch!(opts, :only)
    {config, _} = opts |> Keyword.fetch!(:path) |> Code.eval_file()

    defaults =
      for {group, settings} <- config[:defaults] || [] do
        {group, validate!(settings, @group_schema, "group #{group}")}
      end

    config
    |> Keyword.fetch!(:repos)
    |> filter_repos(only)
    |> Enum.map(fn {name, spec} ->
      resolve(defaults, name, validate!(spec, @repo_schema, "repo #{name}"))
    end)
  end

  defp default_path do
    if File.exists?(@override), do: @override, else: @path
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

  defp validate!(settings, schema, context) do
    case NimbleOptions.validate(settings, schema) do
      {:ok, validated} ->
        validated

      {:error, error} ->
        raise ArgumentError, """
        Invalid configuration for #{context}.

        #{Exception.message(error)}
        """
    end
  end

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
