defmodule ElixirBaseline.Check do
  @moduledoc """
  Reports whether a repo's generated files match what the templates render.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.GH
  alias ElixirBaseline.Render

  @type finding ::
          :ok | :missing | {:differs, pos_integer} | {:error, String.t()}

  @doc """
  Compares every generated file of a resolved repo against the templates.

  Returns one finding per file, ordered by path.

  `fetcher` takes a REST path and returns what `GH.get/1` returns.
  """
  @spec run(map, (String.t() -> GH.result())) :: [{String.t(), finding}]
  def run(spec, fetcher \\ &GH.get/1) do
    spec
    |> Render.files()
    |> Enum.sort()
    |> Enum.map(fn {path, expected} ->
      {path, compare(fetch(spec, path, fetcher), expected)}
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

  defp compare({:ok, actual}, expected) do
    if String.trim(actual) == String.trim(expected) do
      :ok
    else
      {:differs, uncommon_lines(actual, expected)}
    end
  end

  defp compare(finding, _expected), do: finding

  defp uncommon_lines(actual, expected) do
    a = actual |> String.split("\n") |> MapSet.new()
    b = expected |> String.split("\n") |> MapSet.new()

    MapSet.size(MapSet.difference(a, b)) + MapSet.size(MapSet.difference(b, a))
  end
end
