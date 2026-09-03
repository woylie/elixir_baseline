defmodule ElixirBaseline.Repository do
  @moduledoc """
  Resolves what GitHub says about a repo onto its spec.

  One query per repo, before anything renders.
  """

  alias ElixirBaseline.Config
  alias ElixirBaseline.GH

  @type graphql :: (String.t(), keyword -> GH.result())
  @type get :: (String.t() -> GH.result())

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
  @spec resolve_all([map], graphql, get) :: [map]
  def resolve_all(specs, graphql \\ &GH.graphql/2, get \\ &GH.get/1) do
    specs
    |> Task.async_stream(&resolve(&1, graphql, get),
      ordered: true,
      max_concurrency: @concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, spec} -> spec end)
  end

  @doc """
  Returns the spec with `:visibility`, `:security_policy` and `:tree` set.

  `:tree` holds every file path in the repo, at the default branch.

  A repo that could not be read is taken as public with an empty tree, and
  holds the reason under `:error`, so that every check reports the reason
  rather than a fact read from half a repo.
  """
  @spec resolve(map, graphql, get) :: map
  def resolve(spec, graphql \\ &GH.graphql/2, get \\ &GH.get/1) do
    with {:ok, facts} <- facts(spec, graphql),
         {:ok, tree} <- tree(spec, get) do
      Map.merge(spec, Map.put(facts, :tree, tree))
    else
      {:error, reason} -> failed(spec, reason)
    end
  end

  defp facts(spec, graphql) do
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
        {:ok,
         %{
           visibility: if(private, do: :private, else: :public),
           security_policy: policy
         }}

      {:ok, other} ->
        {:error, "unexpected response: #{inspect(other)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp tree(spec, get) do
    case get.("repos/#{Config.slug(spec)}/git/trees/HEAD?recursive=1") do
      {:ok, %{"tree" => entries, "truncated" => false}} ->
        {:ok, paths(entries)}

      {:ok, %{"truncated" => true}} ->
        {:error, "the repository tree came back truncated"}

      {:ok, other} ->
        {:error, "unexpected response: #{inspect(other)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp paths(entries) do
    for %{"type" => "blob", "path" => path} <- entries,
        into: MapSet.new(),
        do: path
  end

  defp failed(spec, reason) do
    Map.merge(spec, %{visibility: :public, tree: MapSet.new(), error: reason})
  end
end
