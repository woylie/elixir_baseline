defmodule ElixirBaseline.Config do
  @moduledoc """
  Reads `.baseline.override.exs`, or `.baseline.exs` if there is no override,
  and resolves each repo's settings.

  Lookup order:

  - project configuration
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
    ],
    templates: [
      type:
        {:list,
         {:or,
          [{:in, [:default]}, {:custom, __MODULE__, :validate_directory, []}]}}
    ],
    include: [type: {:list, :string}],
    exclude: [type: {:list, :string}],
    seed: [
      type: {:list, :string},
      doc: """
      Templates written once and then owned by the project, rather than \
      compared and overwritten.\
      """
    ],
    conditions: [
      type: {:map, :string, {:custom, __MODULE__, :validate_condition, []}},
      doc: """
      Condition a template has to meet to be generated, keyed by template \
      name.\
      """
    ],
    extra: [type: :keyword_list]
  ]

  @group_option [
    group: [
      type: {:or, [:atom, {:list, :atom}]},
      doc: """
      References one or multiple groups defined under `defaults`.
      """
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
    defaults = defaults(config[:defaults] || [])

    config
    |> Keyword.fetch!(:repos)
    |> unique_keys!("repo")
    |> filter_repos(only)
    |> Enum.map(fn {name, spec} ->
      unique_projects!(spec)
      spec = validate!(spec, @repo_schema, "repo #{name}")

      defaults
      |> repo(name, group!(spec, defaults, "repo #{name}"))
      |> owner!(name)
    end)
  end

  defp defaults(groups) do
    groups
    |> unique_keys!("group")
    |> Enum.map(fn {group, settings} ->
      {group, validate!(settings, @group_schema, "group #{group}")}
    end)
  end

  # NimbleOptions drops a duplicate key while validating a keyword list, so
  # this has to read the spec as it was written.
  defp unique_projects!(spec) do
    with true <- Keyword.keyword?(spec),
         projects when is_list(projects) <- Keyword.get(spec, :projects) do
      unique_keys!(projects, "project")
    end
  end

  defp unique_keys!(entries, kind) do
    case Keyword.keys(entries) -- Enum.uniq(Keyword.keys(entries)) do
      [] ->
        entries

      [name | _] ->
        raise ArgumentError, """
        Duplicate #{kind}: #{name}.

        Each #{kind} is written once. Two entries under one name are read as
        two things when they are meant as one.
        """
    end
  end

  defp groups(spec), do: List.wrap(spec[:group])

  defp groups(project, repo) do
    case groups(project) do
      [] -> groups(repo)
      groups -> groups
    end
  end

  defp group!(spec, defaults, context) do
    Enum.each(groups(spec), fn group ->
      cond do
        group == :all -> raise ArgumentError, reserved_group(context)
        Keyword.has_key?(defaults, group) -> :ok
        true -> raise ArgumentError, unknown_group(context, group, defaults)
      end
    end)

    spec
  end

  defp reserved_group(context) do
    """
    Invalid group for #{context}: all.

    The `all` group under `defaults` applies to everything, so it cannot also
    be named as a group of its own.
    """
  end

  defp unknown_group(context, group, defaults) do
    known = defaults |> Keyword.keys() |> List.delete(:all) |> inspect()

    """
    Unknown group for #{context}: #{group}.

    A group is one of the entries under `defaults`.

      known: #{known}
    """
  end

  defp owner!(%{owner: _} = repo, _name), do: repo

  defp owner!(_repo, name) do
    raise ArgumentError, """
    Missing owner for repo #{name}.

    A repo needs an owner to be addressed on GitHub. Set it on the repo, or on
    a group under `defaults` for every repo that shares one.
    """
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
  @spec validate_directory(term) :: {:ok, String.t()} | {:error, String.t()}
  def validate_directory(path) when is_binary(path) do
    scopes = ElixirBaseline.Render.scopes()

    cond do
      not File.dir?(path) ->
        {:error, "expected a directory, got: #{inspect(path)}"}

      not Enum.any?(scopes, &File.dir?(Path.join(path, &1))) ->
        {:error,
         "expected a directory holding #{Enum.join(scopes, " or ")}, " <>
           "got: #{inspect(path)}"}

      true ->
        {:ok, path}
    end
  end

  def validate_directory(other) do
    {:error, "expected a string, got: #{inspect(other)}"}
  end

  @doc false
  @spec validate_condition(term) :: {:ok, tuple} | {:error, String.t()}
  def validate_condition({:exists, path} = condition) when is_binary(path) do
    {:ok, condition}
  end

  def validate_condition(other) do
    {:error, "expected {:exists, path}, got: #{inspect(other)}"}
  end

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
    own = Keyword.delete(spec, :projects)
    settings = collapse(levels(defaults, groups(spec), [own]))

    projects =
      for {project_name, project} <- projects(spec, name) do
        project = group!(project, defaults, "project #{project_name}")
        path = Keyword.get(project, :path, to_string(project_name))

        defaults
        |> levels(groups(project, spec), [own, project])
        |> collapse()
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

  defp levels(defaults, groups, explicit) do
    sources = [@defaults, defaults]

    all =
      for level <- sources, settings = level[:all], not is_nil(settings) do
        settings
      end

    grouped =
      for group <- groups,
          level <- sources,
          settings = level[group],
          not is_nil(settings) do
        settings
      end

    all ++ grouped ++ explicit
  end

  defp collapse(levels) do
    levels |> Enum.reduce([], &merge(&2, &1)) |> Map.new()
  end

  defp merge(base, override), do: Keyword.merge(base, override, &merge_option/3)

  defp merge_option(:extra, base, override), do: Keyword.merge(base, override)
  defp merge_option(:conditions, base, override), do: Map.merge(base, override)
  defp merge_option(_option, _base, override), do: override
end
