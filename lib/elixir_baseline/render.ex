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

  @doc """
  Returns every generated file of a resolved repo, keyed by its path in that
  repo.
  """
  @spec files(map) :: %{String.t() => String.t()}
  def files(repo) do
    projects = Enum.flat_map(repo.projects, &scope(&1, "project", &1.path))

    Map.new(scope(repo, "repo", ".") ++ projects)
  end

  defp scope(settings, scope, path) do
    for {relative, source} <- templates(scope) do
      {destination(path, relative), contents(source, relative, settings)}
    end
  end

  defp templates(scope) do
    dir = Application.app_dir(:elixir_baseline, ["priv", "templates", scope])

    collect(dir, dir)
  end

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

  defp destination(".", relative), do: strip(relative)
  defp destination(path, relative), do: Path.join(path, strip(relative))

  defp strip(relative), do: String.replace_suffix(relative, ".eex", "")

  defp contents(source, relative, settings) do
    if String.ends_with?(relative, ".eex") do
      source
      |> EEx.eval_file(assigns: settings)
      |> format(strip(relative), settings)
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
