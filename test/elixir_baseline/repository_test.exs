defmodule ElixirBaseline.RepositoryTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Repository

  @spek %{name: :spek, owner: "acme"}

  defp graphql(private, policy) do
    answering(%{"isPrivate" => private, "isSecurityPolicyEnabled" => policy})
  end

  defp answering(repository) do
    fn _query, [owner: "acme", name: name] when is_binary(name) ->
      {:ok, %{"repository" => repository}}
    end
  end

  describe "resolve/2" do
    test "resolves a public repo with a policy in force" do
      assert Repository.resolve(@spek, graphql(false, true)) ==
               Map.merge(@spek, %{visibility: :public, security_policy: true})
    end

    test "resolves a private repo without one" do
      assert Repository.resolve(@spek, graphql(true, false)) ==
               Map.merge(@spek, %{visibility: :private, security_policy: false})
    end

    test "takes a repo it could not read as public, and holds the reason" do
      graphql = fn _query, _variables -> {:error, {:http, 404, "Not Found"}} end

      assert %{visibility: :public, error: reason} =
               Repository.resolve(@spek, graphql)

      assert reason == "{:http, 404, \"Not Found\"}"
      refute Map.has_key?(Repository.resolve(@spek, graphql), :security_policy)
    end

    test "reads a renamed field as a failure, not as a private repo" do
      assert %{visibility: :public, error: reason} =
               Repository.resolve(@spek, answering(%{"isPrivate" => false}))

      assert reason =~ "unexpected response"
    end

    test "reads a repo that is not there as a failure" do
      assert %{visibility: :public, error: reason} =
               Repository.resolve(@spek, answering(nil))

      assert reason =~ "unexpected response"
    end
  end

  describe "resolve_all/2" do
    test "resolves every repo in the order they were given" do
      specs = for name <- [:a, :b, :c], do: %{name: name, owner: "acme"}

      resolved = Repository.resolve_all(specs, graphql(false, true))

      assert Enum.map(resolved, & &1.name) == [:a, :b, :c]
      assert Enum.all?(resolved, &(&1.visibility == :public))
    end
  end
end
