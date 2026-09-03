defmodule ElixirBaseline.Render do
  @moduledoc """
  Renders a repo's generated files from the template directories.

  A template directory holds a `repo` and a `project` directory. Everything
  under `repo` is generated once at the repository root, from the repo's own
  settings. Everything under `project` is generated once per project, under
  that project's path, from that project's settings.

  A template ending in `.eex` is rendered with the resolved settings as assigns
  and loses the extension, and generates no file if it renders to nothing.
  Any other file is copied as it is.

  A template named under `conditions` is generated only for a repo that meets
  its condition, so a repo opts in by holding the file the condition names
  rather than by naming the template.

  A template named under `seed` is written once and then belongs to the
  project. `files/1` returns the templates this tool owns and compares, and
  `seeds/1` the seeded ones, which are written only if there is no file yet.
  """

  @scopes ["repo", "project"]

  @doc """
  Returns the scopes a template directory is divided into.
  """
  @spec scopes :: [String.t()]
  def scopes, do: @scopes

  @doc """
  Returns the path every project template takes under its project, whatever
  `include`, `exclude` and `conditions` select.

  The check for a project nobody configured looks for the names this tool
  would generate rather than the ones it does.
  """
  @spec project_paths(map) :: [String.t()]
  def project_paths(settings) do
    for {relative, _source} <- templates(settings, "project"), do: relative
  end

  @doc """
  Returns every owned file of a resolved repo, keyed by its path in that repo.

  An owned file is compared against the template and overwritten if it
  differs.
  """
  @spec files(map) :: %{String.t() => String.t()}
  def files(repo), do: rendered(repo, :owned)

  @doc """
  Returns every seeded file of a resolved repo, keyed by its path in that repo.

  A seeded file is written if there is none and left alone after that, so its
  contents are what the repo starts from rather than what it has to match.
  """
  @spec seeds(map) :: %{String.t() => String.t()}
  def seeds(repo), do: rendered(repo, :seeded)

  defp rendered(repo, mode) do
    selected!(repo)

    projects =
      Enum.flat_map(
        repo.projects,
        &scope(&1, "project", &1.path, repo.tree, mode)
      )

    Map.new(scope(repo, "repo", ".", repo.tree, mode) ++ projects)
  end

  defp selected!(repo) do
    levels = [repo | repo.projects]

    known =
      for settings <- levels,
          scope <- @scopes,
          {relative, _} <- templates(settings, scope),
          into: MapSet.new(),
          do: Path.join(scope, relative)

    for settings <- levels,
        {option, name} <- named(settings),
        name not in known do
      raise ArgumentError, """
      Unknown template in #{option} for repo #{repo.name}.

      A template is named the way it sits in the template directory, scope and
      all, without the `.eex`.

        name: #{inspect(name)}
        known: #{known |> Enum.sort() |> inspect()}
      """
    end
  end

  defp named(settings) do
    lists =
      for option <- [:include, :exclude, :seed],
          name <- Map.get(settings, option) || [],
          do: {option, name}

    conditions =
      for name <- Map.keys(Map.get(settings, :conditions, %{})),
          do: {:conditions, name}

    lists ++ conditions
  end

  defp scope(settings, scope, path, tree, mode) do
    settings
    |> selected(scope, tree, mode)
    |> Enum.flat_map(fn {relative, source} ->
      contents = contents(source, relative, settings)

      if generated?(source, contents) do
        [{destination(path, relative), contents}]
      else
        []
      end
    end)
  end

  defp generated?(source, contents) do
    not String.ends_with?(source, ".eex") or String.trim(contents) != ""
  end

  defp selected(settings, scope, tree, mode) do
    Enum.filter(templates(settings, scope), fn {relative, _} ->
      template = Path.join(scope, relative)

      generate?(template, settings, tree) and mode(template, settings) == mode
    end)
  end

  defp mode(template, settings) do
    if template in Map.get(settings, :seed, []), do: :seeded, else: :owned
  end

  defp templates(settings, scope) do
    settings
    |> Map.get(:templates, [:default])
    |> Enum.flat_map(fn dir ->
      root = Path.join(directory(dir), scope)

      for {relative, source} <- collect(root, root),
          do: {strip(relative), source}
    end)
    |> Map.new()
    |> Enum.sort()
  end

  defp generate?(template, settings, tree) do
    included?(template, Map.get(settings, :include)) and
      template not in Map.get(settings, :exclude, []) and
      holds?(Map.get(settings, :conditions, %{})[template], tree)
  end

  defp included?(_template, nil), do: true
  defp included?(template, include), do: template in include

  defp holds?(nil, _tree), do: true
  defp holds?({:exists, path}, tree), do: path in tree

  defp directory(:default) do
    Application.app_dir(:elixir_baseline, ["priv", "templates"])
  end

  defp directory(path), do: path

  defp collect(root, dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, &collect(root, Path.join(dir, &1)))

      {:error, :enotdir} ->
        [{Path.relative_to(dir, root), dir}]

      {:error, :enoent} ->
        []
    end
  end

  defp destination(".", relative), do: relative
  defp destination(path, relative), do: Path.join(path, relative)

  defp strip(relative), do: String.replace_suffix(relative, ".eex", "")

  defp contents(source, destination, settings) do
    if String.ends_with?(source, ".eex") do
      source
      |> EEx.eval_file(assigns: Map.put_new(settings, :extra, []))
      |> format(destination, settings)
    else
      File.read!(source)
    end
  end

  # Only the Elixir files are formatted, and to the line length they are
  # generated with, so that the file and the check agree on both.
  defp format(source, destination, %{line_length: line_length}) do
    if Path.extname(destination) in [".ex", ".exs"] do
      source
      |> Code.format_string!(line_length: line_length)
      |> IO.iodata_to_binary()
      |> Kernel.<>("\n")
    else
      source
    end
  end
end
