defmodule ElixirBaseline.Render do
  @moduledoc """
  Renders the generated files from `priv/templates`.
  """

  @credo ".credo.exs"

  @doc """
  Returns every generated file of a resolved repo, keyed by its path in that
  repo.
  """
  @spec files(map) :: %{String.t() => String.t()}
  def files(spec) do
    Map.new([spec | spec.subprojects], fn project ->
      {path(project, @credo), credo(project)}
    end)
  end

  defp path(%{path: "."}, file), do: file
  defp path(%{path: dir}, file), do: Path.join(dir, file)

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
