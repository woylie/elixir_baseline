defmodule ElixirBaseline.Check.Settings do
  @moduledoc """
  Reports whether a repo's GitHub settings match the baseline.

  Read-only, and separate from `ElixirBaseline.Check` because a setting is
  changed in GitHub rather than in a pull request, so `mix baseline.pr` has
  nothing to commit for one.

  Takes a spec `ElixirBaseline.Repository` has resolved.

  Each check states its own remedy, because a setting cannot be fixed by
  re-running a task and where to change it differs per setting.

  A setting that does not exist on a repo is `:skipped`, never drift. Both are
  public-only.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.GH

  @type finding ::
          :ok
          | {:drift, state :: String.t(), remedy :: String.t()}
          | {:skipped, String.t()}
          | {:error, String.t()}

  @type get :: (String.t() -> GH.result())

  @policy "security policy"
  @reporting "private vulnerability reporting"

  @labels [@policy, @reporting]

  @doc """
  Returns one finding per setting, ordered as `labels/0` is.

  `get` takes what `GH.get/1` takes, so the skip and drift paths can be tested
  without a repo that exhibits them.
  """
  @spec run(map, get) :: [{String.t(), finding}]
  def run(spec, get \\ &GH.get/1) do
    [{@policy, policy(spec)}, {@reporting, reporting(spec, get)}]
  end

  @doc """
  Returns the label of every setting checked, in report order.
  """
  @spec labels :: [String.t()]
  def labels, do: @labels

  @doc """
  Returns true when every applicable setting matches.
  """
  @spec ok?([{String.t(), finding}]) :: boolean
  def ok?(findings) do
    Enum.all?(findings, fn {_label, finding} ->
      finding == :ok or match?({:skipped, _reason}, finding)
    end)
  end

  defp policy(%{error: reason}), do: {:error, reason}

  # No `SECURITY.md` is generated for a private repo, so drift here is
  # unfixable.
  defp policy(%{visibility: :private}), do: {:skipped, "private repository"}

  defp policy(%{security_policy: true}), do: :ok

  defp policy(_spec), do: {:drift, "none", "run: mix baseline.pr"}

  defp reporting(%{error: reason}, _get), do: {:error, reason}

  # Nobody outside a private repo can report anything to it, so the setting
  # does not exist there and the endpoint answers 404.
  defp reporting(%{visibility: :private}, _get) do
    {:skipped, "private repository"}
  end

  defp reporting(spec, get) do
    case get.(reporting_path(spec)) do
      {:ok, %{"enabled" => true}} -> :ok
      {:ok, %{"enabled" => false}} -> disabled(spec)
      {:ok, other} -> {:error, "unexpected response: #{inspect(other)}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # The API rather than the settings page, because it is exact, it is what the
  # rest of this tool already needs `gh` for, and GitHub renames the page.
  defp disabled(spec) do
    {:drift, "disabled", "run: gh api --method PUT #{reporting_path(spec)}"}
  end

  defp reporting_path(spec) do
    "repos/#{Config.slug(spec)}/private-vulnerability-reporting"
  end
end
