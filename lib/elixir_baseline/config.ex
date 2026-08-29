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

  @path_option [
    path: [
      type: {:custom, __MODULE__, :validate_path, []},
      doc: "Directory the project lives in, relative to the repository root."
    ]
  ]

  @group_schema NimbleOptions.new!([owner: [type: :string]] ++ @settings)

  @project_schema @group_option ++ @path_option ++ @settings

  @repo_schema NimbleOptions.new!(
                 [
                   owner: [type: :string, doc: "GitHub owner of the repo."],
                   projects: [
                     type: :keyword_list,
                     keys: [*: [type: :keyword_list, keys: @project_schema]],
                     doc: """
                     The Mix projects in the repo, keyed by name. Defaults to \
                     one project named after the repo, at its root.\
                     """
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
  Returns the `owner/repo` slug of a resolved repo or project.
  """
  @spec slug(map) :: String.t()
  def slug(%{owner: owner, name: name}), do: "#{owner}/#{name}"

  @doc false
  @spec validate_path(term) :: {:ok, String.t()} | {:error, String.t()}
  def validate_path(path) when is_binary(path) do
    if Path.type(path) == :relative and ".." not in Path.split(path) and
         path != "" do
      {:ok, Path.relative_to(path, ".")}
    else
      {:error, "expected a path inside the repository, got: #{inspect(path)}"}
    end
  end

  def validate_path(other) do
    {:error, "expected a string, got: #{inspect(other)}"}
  end

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
    settings = resolve(defaults, [], spec)

    projects =
      for {project_name, project} <- projects(spec, name) do
        path = Keyword.get(project, :path, to_string(project_name))

        defaults
        |> resolve(Map.to_list(settings), project)
        |> Map.merge(%{name: name, path: path})
      end

    settings
    |> Map.merge(%{name: name, projects: projects})
    |> unique_paths!()
  end

  defp projects(spec, name) do
    Keyword.get_lazy(spec, :projects, fn -> [{name, [path: "."]}] end)
  end

  defp unique_paths!(repo) do
    paths = Enum.map(repo.projects, & &1.path)

    case paths -- Enum.uniq(paths) do
      [] ->
        repo

      [path | _] ->
        raise ArgumentError, """
        Duplicate project path in repo #{repo.name}.

        Every project in a repository generates its own files, so two of them
        cannot live at the same path.

          path: #{inspect(path)}
        """
    end
  end

  # `base` is the repo's resolved settings for a project, and empty for the
  # repo itself, so both resolve through the same levels.
  defp resolve(defaults, base, spec) do
    spec = base |> Keyword.merge(spec) |> Keyword.delete(:projects)

    [@defaults, defaults]
    |> Enum.flat_map(&[&1[:all], &1[spec[:group]]])
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce([], &Keyword.merge(&2, &1))
    |> Keyword.merge(spec)
    |> Map.new()
  end
end
