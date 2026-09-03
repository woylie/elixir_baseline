defmodule ElixirBaseline.Check.Unclaimed do
  @moduledoc """
  Reports a project in a repo that the config does not enroll.

  The drift check looks only at the paths the config expects, so a project
  nobody configured is invisible to it and the repo reads as covered. This
  searches the other way, over every path in the repo, for a file this tool
  would generate for a project sitting in a directory no configured project
  claims.

  Takes a spec `ElixirBaseline.Repository` has resolved, and makes no request
  of its own: the repo's tree is already on the spec.
  """

  alias ElixirBaseline.Render

  @type finding :: {:drift, state :: String.t(), remedy :: String.t()}

  # Every Mix project has one, so an unenrolled project is found even if it has
  # none of the generated files yet.
  @manifest "mix.exs"

  @doc """
  Returns one finding per unclaimed file, ordered by path.

  A repo that could not be resolved returns nothing, because its tree is empty
  and `ElixirBaseline.Check` already reports the reason against every file.
  """
  @spec run(map) :: [{String.t(), finding}]
  def run(%{error: _reason}), do: []

  def run(spec) do
    claimed = MapSet.new(spec.projects, & &1.path)
    generated = generated(spec)

    for path <- Enum.sort(spec.tree),
        directory = directory(path, generated),
        directory != nil,
        directory not in claimed,
        do: {path, unclaimed(directory)}
  end

  @doc """
  Returns true when every project in a checked repo is enrolled.
  """
  @spec ok?([{String.t(), finding}]) :: boolean
  def ok?(findings), do: findings == []

  defp generated(spec) do
    for settings <- [spec | spec.projects],
        relative <- [@manifest | Render.project_paths(settings)],
        into: MapSet.new(),
        do: relative
  end

  # The directory the file would be a project's own, or nil if it is not a
  # generated name at all.
  defp directory(path, generated) do
    Enum.find_value(generated, fn relative ->
      cond do
        template?(path, relative) -> nil
        path == relative -> "."
        String.ends_with?(path, "/" <> relative) -> parent(path, relative)
        true -> nil
      end
    end)
  end

  defp template?(path, relative) do
    Enum.any?(Render.scopes(), fn scope ->
      suffix = "#{scope}/#{relative}"

      path == suffix or String.ends_with?(path, "/" <> suffix)
    end)
  end

  defp parent(path, relative) do
    String.replace_suffix(path, "/" <> relative, "")
  end

  defp unclaimed(".") do
    {:drift, "unclaimed", "add a project at the repository root to projects:"}
  end

  defp unclaimed(directory) do
    {:drift, "unclaimed", "add a project with path: #{inspect(directory)}"}
  end
end
