defmodule ElixirBaseline.GH do
  @moduledoc """
  Read-only wrapper around the `gh` CLI.
  """

  @type result ::
          {:ok, term}
          | {:error, {:http, pos_integer, String.t()}}
          | {:error, String.t()}

  @doc """
  Returns the decoded JSON body of a GET request to a REST path.
  """
  @spec get(String.t()) :: result
  def get(path) do
    case System.cmd("gh", ["api", path], stderr_to_stdout: true) do
      {out, 0} -> {:ok, JSON.decode!(out)}
      {out, _} -> {:error, failure(out)}
    end
  end

  defp failure(out) do
    case Regex.run(~r/gh: (.+) \(HTTP (\d{3})\)/, out) do
      [_, message, status] -> {:http, String.to_integer(status), message}
      _ -> String.trim(out)
    end
  end
end
