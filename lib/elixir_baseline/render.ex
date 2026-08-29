defmodule ElixirBaseline.Render do
  @moduledoc """
  Renders a repo's generated files from the template directories.

  A template directory holds a `repo` and a `project` directory. Everything
  under `repo` is generated once at the repository root, from the repo's own
  settings. Everything under `project` is generated once per project, under
  that project's path, from that project's settings.

  A template ending in `.eex` is rendered with the resolved settings as assigns
  and loses the extension. Any other file is copied as it is.
  """

  @scopes ["repo", "project"]

  @doc """
  Returns the scopes a template directory is divided into.
  """
  @spec scopes :: [String.t()]
  def scopes, do: @scopes

  @doc """
  Returns every generated file of a resolved repo, keyed by its path in that
  repo.
  """
  @spec files(map) :: %{String.t() => String.t()}
  def files(repo) do
    selected!(repo)

    projects = Enum.flat_map(repo.projects, &scope(&1, "project", &1.path))

    Map.new(scope(repo, "repo", ".") ++ projects)
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
        option <- [:include, :exclude],
        name <- Map.get(settings, option) || [],
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

  defp scope(settings, scope, path) do
    for {relative, source} <- selected(settings, scope) do
      {destination(path, relative), contents(source, relative, settings)}
    end
  end

  defp selected(settings, scope) do
    Enum.filter(templates(settings, scope), fn {relative, _} ->
      generate?(Path.join(scope, relative), settings)
    end)
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

  defp generate?(template, settings) do
    included?(template, Map.get(settings, :include)) and
      template not in Map.get(settings, :exclude, [])
  end

  defp included?(_template, nil), do: true
  defp included?(template, include), do: template in include

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
      |> EEx.eval_file(assigns: settings)
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
