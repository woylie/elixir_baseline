defmodule ElixirBaseline.Repository do
  @moduledoc """
  Resolves what GitHub says about a repo onto its spec.

  One query per repo, before anything renders.
  """

  alias ElixirBaseline.GH

  @type graphql :: (String.t(), keyword -> GH.result())

  @concurrency 4

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
  Resolves every repo concurrently, in order.
  """
  @spec resolve_all([map], graphql) :: [map]
  def resolve_all(specs, graphql \\ &GH.graphql/2) do
    specs
    |> Task.async_stream(&resolve(&1, graphql),
      ordered: true,
      max_concurrency: @concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, spec} -> spec end)
  end

  @doc """
  Returns the spec with `:visibility` and `:security_policy` set.

  A repo that could not be read is taken as public, so the failure does not
  drop its security policy, and holds the reason under `:error`.
  """
  @spec resolve(map, graphql) :: map
  def resolve(spec, graphql \\ &GH.graphql/2) do
    case graphql.(@query, owner: spec.owner, name: to_string(spec.name)) do
      # A missing field must not read as false.
      {:ok,
       %{
         "repository" => %{
           "isPrivate" => private,
           "isSecurityPolicyEnabled" => policy
         }
       }}
      when is_boolean(private) and is_boolean(policy) ->
        Map.merge(spec, %{
          visibility: if(private, do: :private, else: :public),
          security_policy: policy
        })

      {:ok, other} ->
        failed(spec, "unexpected response: #{inspect(other)}")

      {:error, reason} ->
        failed(spec, inspect(reason))
    end
  end

  defp failed(spec, reason) do
    Map.merge(spec, %{visibility: :public, error: reason})
  end
end
