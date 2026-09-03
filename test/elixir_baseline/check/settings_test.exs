defmodule ElixirBaseline.Check.SettingsTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check.Settings

  @policy "security policy"
  @reporting "private vulnerability reporting"
  @secrets "repository secrets"

  @path "repos/acme/spek/private-vulnerability-reporting"
  @secrets_path "repos/acme/spek/actions/secrets"

  @enable "run: gh api --method PUT #{@path}"
  @add "run: mix baseline.pr"
  @move "move each secret into an environment with required reviewers"

  defp spec(resolved) do
    Enum.into(resolved, %{name: :spek, owner: "acme", visibility: :public})
  end

  defp get(enabled, names \\ []) do
    secrets = for name <- names, do: %{"name" => name}

    fn
      @path -> {:ok, %{"enabled" => enabled}}
      @secrets_path -> {:ok, %{"secrets" => secrets}}
    end
  end

  defp unread do
    fn _path -> flunk("fetched") end
  end

  describe "run/2" do
    test "is ok when every setting matches" do
      spec = spec(security_policy: true)

      assert Settings.run(spec, get(true)) ==
               [{@policy, :ok}, {@reporting, :ok}, {@secrets, :ok}]
    end

    test "says where to enable reporting that is disabled" do
      spec = spec(security_policy: true)

      assert Settings.run(spec, get(false)) ==
               [
                 {@policy, :ok},
                 {@reporting, {:drift, "disabled", @enable}},
                 {@secrets, :ok}
               ]
    end

    test "says how to write the policy of a repo that has none" do
      spec = spec(security_policy: false)

      assert Settings.run(spec, get(true)) ==
               [
                 {@policy, {:drift, "none", @add}},
                 {@reporting, :ok},
                 {@secrets, :ok}
               ]
    end

    test "names every ungated secret of a public repo, in order" do
      spec = spec(security_policy: true)
      get = get(true, ["FLY_API_TOKEN", "AWS_KEY"])

      assert {@secrets, {:drift, state, @move}} =
               List.last(Settings.run(spec, get))

      assert state == "2 ungated: AWS_KEY, FLY_API_TOKEN"
    end

    test "skips every setting on a private repo without asking for any" do
      skipped = {:skipped, "private repository"}

      for policy <- [true, false] do
        spec = spec(security_policy: policy, visibility: :private)

        assert Settings.run(spec, unread()) ==
                 [
                   {@policy, skipped},
                   {@reporting, skipped},
                   {@secrets, skipped}
                 ]
      end
    end

    test "reports every setting when the repo could not be resolved" do
      spec = spec(error: "\"Could not resolve\"")
      error = {:error, "\"Could not resolve\""}

      assert Settings.run(spec, unread()) ==
               [{@policy, error}, {@reporting, error}, {@secrets, error}]
    end

    test "reports a failed reporting request as an error" do
      spec = spec(security_policy: true)
      get = fn _path -> {:error, {:http, 403, "Forbidden"}} end
      error = {:error, "{:http, 403, \"Forbidden\"}"}

      assert Settings.run(spec, get) ==
               [{@policy, :ok}, {@reporting, error}, {@secrets, error}]
    end

    test "reports an unexpected response as an error" do
      spec = spec(security_policy: true)
      get = fn _path -> {:ok, %{"on" => true}} end

      assert [{@policy, :ok}, {@reporting, reporting}, {@secrets, secrets}] =
               Settings.run(spec, get)

      assert {:error, reason} = reporting
      assert reason =~ "unexpected response"
      assert {:error, reason} = secrets
      assert reason =~ "unexpected response"
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
      assert Settings.labels() == [@policy, @reporting, @secrets]
    end
  end
end
