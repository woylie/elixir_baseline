defmodule ElixirBaseline.Diff do
  @moduledoc """
  Line differences between a file as it stands and as a template renders it.
  """

  @type t :: [{:eq | :del | :ins, [String.t()]}]

  @doc """
  Returns the edits that turn `actual` into `expected`, by line.
  """
  @spec lines(String.t(), String.t()) :: t
  def lines(actual, expected) do
    List.myers_difference(split(actual), split(expected))
  end

  @doc """
  Returns how many lines a template adds and removes.
  """
  @spec counts(t) :: {non_neg_integer, non_neg_integer}
  def counts(diff), do: {count(diff, :ins), count(diff, :del)}

  @doc """
  Returns the changed lines, each marked with what happens to it.
  """
  @spec format(t) :: String.t()
  def format(diff) do
    diff
    |> Enum.reject(fn {edit, _lines} -> edit == :eq end)
    |> Enum.map_join("\n", fn {edit, lines} ->
      Enum.map_join(lines, "\n", &(marker(edit) <> &1))
    end)
  end

  defp split(contents),
    do: contents |> String.trim_trailing() |> String.split("\n")

  defp count(diff, edit) do
    diff |> Keyword.get_values(edit) |> List.flatten() |> length()
  end

  defp marker(:ins), do: "+"
  defp marker(:del), do: "-"
end
