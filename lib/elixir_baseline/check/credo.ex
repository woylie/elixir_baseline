defmodule ElixirBaseline.Check.Credo do
  @moduledoc """
  Reports whether a repo's `.credo.exs` matches the shared template.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.GH
  alias ElixirBaseline.Render

  @type finding ::
          :ok | :missing | {:differs, pos_integer} | {:error, String.t()}

  @path ".credo.exs"

  @doc """
  Compares a resolved repo's `.credo.exs` against the template.

  `fetcher` takes a REST path and returns what `GH.get/1` returns.
  """
  @spec run(map, (String.t() -> GH.result())) :: finding
  def run(spec, fetcher \\ &GH.get/1) do
    case fetch(spec, fetcher) do
      {:ok, actual} -> compare(actual, Render.credo(spec))
      finding -> finding
    end
  end

  defp fetch(spec, fetcher) do
    case fetcher.("repos/#{Config.slug(spec)}/contents/#{@path}") do
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

  defp compare(actual, expected) do
    if String.trim(actual) == String.trim(expected) do
      :ok
    else
      {:differs, uncommon_lines(actual, expected)}
    end
  end

  defp uncommon_lines(actual, expected) do
    a = actual |> String.split("\n") |> MapSet.new()
    b = expected |> String.split("\n") |> MapSet.new()

    MapSet.size(MapSet.difference(a, b)) + MapSet.size(MapSet.difference(b, a))
  end
end
