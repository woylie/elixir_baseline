defmodule ElixirBaseline.Check do
  @moduledoc """
  Reports whether a repo's generated files match what the templates render.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.Diff
  alias ElixirBaseline.GH
  alias ElixirBaseline.Render

  @workflow ~r{^\.github/workflows/[^/]+\.ya?ml$}
  @uses_ref ~r{(uses:\s*\S+?)@\S+(\s*#.*)?$}m

  @type finding ::
          :ok
          | {:missing, String.t()}
          | {:differs, Diff.t()}
          | {:error, String.t()}

  @doc """
  Compares every generated file of a resolved repo against the templates.

  Returns one finding per file, ordered by path. A missing file holds what the
  template renders, and a differing one holds the difference, so that neither
  has to be read a second time.

  `fetcher` takes a REST path and returns what `GH.get/1` returns.
  """
  @spec run(map, (String.t() -> GH.result())) :: [{String.t(), finding}]
  def run(spec, fetcher \\ &GH.get/1) do
    spec
    |> Render.files()
    |> Enum.sort()
    |> Enum.map(fn {path, expected} ->
      {path, compare(path, fetch(spec, path, fetcher), expected)}
    end)
  end

  @doc """
  Returns true when every file of a checked repo matches.
  """
  @spec ok?([{String.t(), finding}]) :: boolean
  def ok?(findings), do: Enum.all?(findings, &match?({_path, :ok}, &1))

  defp fetch(spec, path, fetcher) do
    case fetcher.("repos/#{Config.slug(spec)}/contents/#{path}") do
      {:ok, %{"content" => body}} ->
        {:ok, Base.decode64!(body, ignore: :whitespace)}

      {:ok, other} ->
        {:error, "unexpected response: #{inspect(other)}"}

      {:error, {:http, 404, _}} ->
        :missing

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp compare(path, {:ok, actual}, expected) do
    if same?(path, actual, expected) do
      :ok
    else
      {:differs, Diff.lines(actual, expected)}
    end
  end

  defp compare(_path, :missing, expected), do: {:missing, expected}
  defp compare(_path, finding, _expected), do: finding

  # A trailing newline is not drift in a text file, but a template copied
  # verbatim can be any bytes, and those are compared as they are.
  defp same?(path, actual, expected) do
    if String.valid?(actual) and String.valid?(expected) do
      String.trim(owned(path, actual)) == String.trim(owned(path, expected))
    else
      actual == expected
    end
  end

  defp owned(path, contents) do
    if Regex.match?(@workflow, path) do
      String.replace(contents, @uses_ref, "\\1")
    else
      contents
    end
  end
end
