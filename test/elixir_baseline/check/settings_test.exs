defmodule ElixirBaseline.Check.SettingsTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check.Settings

  @spek %{name: :spek, owner: "acme"}

  @policy "security policy"
  @reporting "private vulnerability reporting"

  @path "repos/acme/spek/private-vulnerability-reporting"

  @enable "run: gh api --method PUT #{@path}"
  @add "add SECURITY.md to acme/.github"

  defp graphql(private, policy) do
    fn _query, [owner: "acme", name: "spek"] ->
      {:ok,
       %{
         "repository" => %{
           "isPrivate" => private,
           "isSecurityPolicyEnabled" => policy
         }
       }}
    end
  end

  defp get(enabled) do
    fn @path -> {:ok, %{"enabled" => enabled}} end
  end

  describe "run/3" do
    test "is ok when the policy is in force and reporting is enabled" do
      assert Settings.run(@spek, graphql(false, true), get(true)) ==
               [{@policy, :ok}, {@reporting, :ok}]
    end

    test "says where to enable reporting that is disabled" do
      assert Settings.run(@spek, graphql(false, true), get(false)) ==
               [{@policy, :ok}, {@reporting, {:drift, "disabled", @enable}}]
    end

    test "points a repo with no policy at the owner's .github repo" do
      assert Settings.run(@spek, graphql(false, false), get(true)) ==
               [{@policy, {:drift, "none", @add}}, {@reporting, :ok}]
    end

    test "skips reporting on a private repo without asking for it" do
      get = fn path -> flunk("fetched #{path}") end

      assert Settings.run(@spek, graphql(true, true), get) ==
               [{@policy, :ok}, {@reporting, {:skipped, "private repository"}}]
    end

    test "checks the policy of a private repo, which inherits it" do
      get = fn _path -> flunk("fetched") end

      assert {@policy, {:drift, "none", @add}} in Settings.run(
               @spek,
               graphql(true, false),
               get
             )
    end

    test "reports every setting when the repo cannot be read" do
      graphql = fn _query, _variables -> {:error, "Could not resolve"} end
      get = fn _path -> flunk("fetched") end

      assert Settings.run(@spek, graphql, get) ==
               [
                 {@policy, {:error, "\"Could not resolve\""}},
                 {@reporting, {:error, "\"Could not resolve\""}}
               ]
    end

    test "reports an unexpected response as an error" do
      graphql = fn _query, _variables -> {:ok, %{"repository" => nil}} end
      get = fn _path -> flunk("fetched") end

      assert [{@policy, {:error, reason}}, {@reporting, {:error, reason}}] =
               Settings.run(@spek, graphql, get)

      assert reason =~ "unexpected response"
    end

    test "reports a renamed field as an error, not as drift" do
      graphql = fn _query, _variables ->
        {:ok, %{"repository" => %{"isPrivate" => false}}}
      end

      get = fn _path -> flunk("fetched") end

      assert [{@policy, {:error, reason}}, {@reporting, {:error, reason}}] =
               Settings.run(@spek, graphql, get)

      assert reason =~ "unexpected response"
    end

    test "reports a failed reporting request as an error" do
      get = fn @path -> {:error, {:http, 403, "Forbidden"}} end

      assert Settings.run(@spek, graphql(false, true), get) ==
               [
                 {@policy, :ok},
                 {@reporting, {:error, "{:http, 403, \"Forbidden\"}"}}
               ]
    end
  end

  describe "ok?/1" do
    test "is true when every applicable setting matches" do
      assert Settings.ok?([{@policy, :ok}, {@reporting, :ok}])
      assert Settings.ok?([{@policy, :ok}, {@reporting, {:skipped, "private"}}])
    end

    test "is false when a setting drifted or could not be read" do
      refute Settings.ok?([{@reporting, {:drift, "disabled", @enable}}])
      refute Settings.ok?([{@policy, {:error, "boom"}}])
    end
  end

  describe "labels/0" do
    test "names every setting in report order" do
      assert Settings.labels() == [@policy, @reporting]
    end
  end
end
