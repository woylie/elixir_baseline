defmodule ElixirBaseline.Render do
  @moduledoc """
  Renders the generated per-repo files from `priv/templates`.
  """

  @doc """
  Returns the rendered `.credo.exs` for a resolved repo.
  """
  @spec credo(map) :: String.t()
  def credo(%{line_length: line_length}) do
    "credo.exs.eex"
    |> template()
    |> EEx.eval_file(line_length: line_length)
    |> format(line_length)
  end

  defp template(name) do
    Application.app_dir(:elixir_baseline, ["priv", "templates", name])
  end

  defp format(source, line_length) do
    source
    |> Code.format_string!(line_length: line_length)
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end
end
