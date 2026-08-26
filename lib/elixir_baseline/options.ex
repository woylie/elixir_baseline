defmodule ElixirBaseline.Options do
  @moduledoc """
  Shared option handling for the `baseline.*` tasks.
  """

  @doc """
  Returns the options `ElixirBaseline.Config.repos/1` takes, from parsed switches.
  """
  @spec repos(keyword) :: keyword
  def repos(opts) do
    only = Keyword.get_values(opts, :repo)
    opts = [path: opts[:config], only: if(only == [], do: nil, else: only)]

    Enum.reject(opts, fn {_key, value} -> is_nil(value) end)
  end
end
