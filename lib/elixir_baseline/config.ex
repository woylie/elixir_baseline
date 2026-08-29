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

  @group_option [
    group: [
      type: :atom,
      doc: "The group defined under `defaults` this repo belongs to."
    ]
  ]

  @group_schema NimbleOptions.new!([owner: [type: :string]] ++ @settings)

  @subproject_schema @group_option ++ @settings

  @repo_schema NimbleOptions.new!(
                 [
                   owner: [type: :string, doc: "GitHub owner of the repo."],
                   subprojects: [
                     type: :keyword_list,
                     keys: [*: [type: :keyword_list, keys: @subproject_schema]],
                     doc: "Nested Mix projects, keyed by name."
                   ]
                 ] ++ @group_option ++ @settings
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
      repo(defaults, name, validate!(spec, @repo_schema, "repo #{name}"))
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
  Returns the `owner/repo` slug of a resolved repo or subproject.
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

  defp repo(defaults, name, spec) do
    resolved =
      defaults
      |> resolve([], spec)
      |> Map.merge(%{name: name, path: "."})

    subprojects =
      for {subname, subproject} <- Keyword.get(spec, :subprojects, []) do
        defaults
        |> resolve(Map.to_list(resolved), subproject)
        |> Map.merge(%{name: name, path: to_string(subname)})
      end

    Map.put(resolved, :subprojects, subprojects)
  end

  # `base` is the parent's resolved settings for a subproject, and empty for a
  # repo, so both resolve through the same levels.
  defp resolve(defaults, base, spec) do
    spec = base |> Keyword.merge(spec) |> Keyword.delete(:subprojects)

    [@defaults, defaults]
    |> Enum.flat_map(&[&1[:all], &1[spec[:group]]])
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], &Keyword.merge(&2, &1))
    |> Keyword.merge(spec)
    |> Map.new()
  end
end
