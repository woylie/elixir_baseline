defmodule ElixirBaseline.Check.Settings do
  @moduledoc """
  Reports whether a repo's GitHub settings match the baseline.

  Read-only, and separate from `ElixirBaseline.Check` because a setting is
  changed in GitHub rather than in a pull request, so `mix baseline.pr` has
  nothing to commit for one.

  Each check states its own remedy, because a setting cannot be fixed by
  re-running a task and where to change it differs per setting.

  A setting that does not exist on a repo is `:skipped`, never drift.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.GH

  @type finding ::
          :ok
          | {:drift, state :: String.t(), remedy :: String.t()}
          | {:skipped, String.t()}
          | {:error, String.t()}

  @type graphql :: (String.t(), keyword -> GH.result())
  @type get :: (String.t() -> GH.result())

  @policy "security policy"
  @reporting "private vulnerability reporting"

  @labels [@policy, @reporting]

  # `isSecurityPolicyEnabled` is the only field that is true for a policy
  # inherited from the owner's `.github` repo. `community/profile` omits it.
  @query """
  query($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      isPrivate
      isSecurityPolicyEnabled
    }
  }
  """

  @doc """
  Returns one finding per setting, ordered as `labels/0` is.

  `graphql` and `get` take what `GH.graphql/2` and `GH.get/1` take, so the skip
  and drift paths can be tested without a repo that exhibits them.
  """
  @spec run(map, graphql, get) :: [{String.t(), finding}]
  def run(spec, graphql \\ &GH.graphql/2, get \\ &GH.get/1) do
    case graphql.(@query, owner: spec.owner, name: to_string(spec.name)) do
      # A field that is missing or no longer a boolean is a response we did not
      # ask for, not a repo whose settings drifted.
      {:ok,
       %{
         "repository" => %{
           "isPrivate" => private,
           "isSecurityPolicyEnabled" => policy
         }
       }}
      when is_boolean(private) and is_boolean(policy) ->
        [
          {@policy, policy(spec, policy)},
          {@reporting, reporting(spec, private, get)}
        ]

      {:ok, other} ->
        errors("unexpected response: #{inspect(other)}")

      {:error, reason} ->
        errors(inspect(reason))
    end
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

  defp policy(_spec, true), do: :ok

  # One file in the owner's `.github` repo covers every repo of that owner, so
  # the remedy points there rather than at the repo that reported it.
  defp policy(spec, false) do
    {:drift, "none", "add SECURITY.md to #{spec.owner}/.github"}
  end

  # Nobody outside a private repo can report anything to it, so the setting
  # does not exist there and the endpoint answers 404.
  defp reporting(_spec, true, _get) do
    {:skipped, "private repository"}
  end

  defp reporting(spec, false, get) do
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

  # One finding per label either way, so a repo counts the same whether it was
  # read or not.
  defp errors(reason) do
    for label <- @labels, do: {label, {:error, reason}}
  end
end
