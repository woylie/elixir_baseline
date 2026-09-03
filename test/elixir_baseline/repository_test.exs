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

  defp tree(paths) do
    entries = for path <- paths, do: %{"type" => "blob", "path" => path}

    returning(%{
      "tree" => entries ++ [%{"type" => "tree", "path" => "lib"}],
      "truncated" => false
    })
  end

  defp returning(body) do
    fn "repos/acme/" <> _ -> {:ok, body} end
  end

  describe "resolve/3" do
    test "resolves a public repo with a policy in force" do
      assert Repository.resolve(@spek, graphql(false, true), tree(["mix.exs"])) ==
               Map.merge(@spek, %{
                 visibility: :public,
                 security_policy: true,
                 tree: MapSet.new(["mix.exs"])
               })
    end

    test "resolves a private repo without one" do
      assert Repository.resolve(@spek, graphql(true, false), tree([])) ==
               Map.merge(@spek, %{
                 visibility: :private,
                 security_policy: false,
                 tree: MapSet.new()
               })
    end

    test "holds every file in the repo, and no directory" do
      %{tree: tree} =
        Repository.resolve(@spek, graphql(false, true), tree(["a", "lib/b.ex"]))

      assert tree == MapSet.new(["a", "lib/b.ex"])
    end

    test "takes a repo it could not read as public, and holds the reason" do
      graphql = fn _query, _variables -> {:error, {:http, 404, "Not Found"}} end
      resolved = Repository.resolve(@spek, graphql, tree([]))

      assert %{visibility: :public, tree: empty, error: reason} = resolved
      assert reason == "{:http, 404, \"Not Found\"}"
      assert empty == MapSet.new()
      refute Map.has_key?(resolved, :security_policy)
    end

    test "reads a renamed field as a failure, not as a private repo" do
      assert %{visibility: :public, error: reason} =
               Repository.resolve(
                 @spek,
                 answering(%{"isPrivate" => false}),
                 tree([])
               )

      assert reason =~ "unexpected response"
    end

    test "reads a repo that is not there as a failure" do
      assert %{visibility: :public, error: reason} =
               Repository.resolve(@spek, answering(nil), tree([]))

      assert reason =~ "unexpected response"
    end

    test "reads a truncated tree as a failure, not as a short repo" do
      get = returning(%{"tree" => [], "truncated" => true})

      assert %{error: reason} =
               Repository.resolve(@spek, graphql(false, true), get)

      assert reason =~ "truncated"
    end

    test "reports a tree it could not read" do
      get = fn _path -> {:error, {:http, 409, "Git Repository is empty"}} end

      assert %{error: reason} =
               Repository.resolve(@spek, graphql(false, true), get)

      assert reason =~ "409"
    end
  end

  describe "resolve_all/3" do
    test "resolves every repo in the order they were given" do
      specs = for name <- [:a, :b, :c], do: %{name: name, owner: "acme"}

      resolved = Repository.resolve_all(specs, graphql(false, true), tree([]))

      assert Enum.map(resolved, & &1.name) == [:a, :b, :c]
      assert Enum.all?(resolved, &(&1.visibility == :public))
    end
  end
end
