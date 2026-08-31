defmodule ElixirBaseline.GH do
  @moduledoc """
  Read-only wrapper around the `gh` CLI.
  """

  @type result ::
          {:ok, term}
          | {:error, {:http, pos_integer, String.t()}}
          | {:error, String.t()}

  @http ~r/gh: (.+) \(HTTP (\d{3})\)/
  @message ~r/^gh: (.+)$/m

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

  @doc """
  Returns the `data` of a GraphQL query.

  Variables are passed as parameters, so a value never becomes part of the
  query. `gh` exits non-zero whenever the response holds `errors`, so a body
  returned here has none.
  """
  @spec graphql(String.t(), keyword) :: result
  def graphql(query, variables \\ []) do
    args = ["api", "graphql", "-f", "query=#{query}" | fields(variables)]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, JSON.decode!(out)["data"]}
      {out, _} -> {:error, failure(out)}
    end
  end

  defp fields(variables) do
    Enum.flat_map(variables, fn {key, value} -> ["-f", "#{key}=#{value}"] end)
  end

  defp failure(out) do
    case Regex.run(@http, out) do
      [_, message, status] -> {:http, String.to_integer(status), message}
      nil -> message(out)
    end
  end

  defp message(out) do
    case Regex.run(@message, out) do
      [_, message] -> message
      nil -> String.trim(out)
    end
  end
end
