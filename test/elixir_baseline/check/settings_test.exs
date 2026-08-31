defmodule ElixirBaseline.Check.SettingsTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check.Settings

  @policy "security policy"
  @reporting "private vulnerability reporting"

  @path "repos/acme/spek/private-vulnerability-reporting"

  @enable "run: gh api --method PUT #{@path}"
  @add "run: mix baseline.pr"

  defp spec(resolved) do
    Enum.into(resolved, %{name: :spek, owner: "acme", visibility: :public})
  end

  defp get(enabled) do
    fn @path -> {:ok, %{"enabled" => enabled}} end
  end

  defp unread do
    fn _path -> flunk("fetched") end
  end

  describe "run/2" do
    test "is ok when the policy is in force and reporting is enabled" do
      spec = spec(security_policy: true)

      assert Settings.run(spec, get(true)) ==
               [{@policy, :ok}, {@reporting, :ok}]
    end

    test "says where to enable reporting that is disabled" do
      spec = spec(security_policy: true)

      assert Settings.run(spec, get(false)) ==
               [{@policy, :ok}, {@reporting, {:drift, "disabled", @enable}}]
    end

    test "says how to write the policy of a repo that has none" do
      spec = spec(security_policy: false)

      assert Settings.run(spec, get(true)) ==
               [{@policy, {:drift, "none", @add}}, {@reporting, :ok}]
    end

    test "skips both settings on a private repo without asking for either" do
      skipped = {:skipped, "private repository"}

      for policy <- [true, false] do
        spec = spec(security_policy: policy, visibility: :private)

        assert Settings.run(spec, unread()) ==
                 [{@policy, skipped}, {@reporting, skipped}]
      end
    end

    test "reports every setting when the repo could not be resolved" do
      spec = spec(error: "\"Could not resolve\"")

      assert Settings.run(spec, unread()) ==
               [
                 {@policy, {:error, "\"Could not resolve\""}},
                 {@reporting, {:error, "\"Could not resolve\""}}
               ]
    end

    test "reports a failed reporting request as an error" do
      spec = spec(security_policy: true)
      get = fn @path -> {:error, {:http, 403, "Forbidden"}} end

      assert Settings.run(spec, get) ==
               [
                 {@policy, :ok},
                 {@reporting, {:error, "{:http, 403, \"Forbidden\"}"}}
               ]
    end

    test "reports an unexpected reporting response as an error" do
      spec = spec(security_policy: true)
      get = fn @path -> {:ok, %{"on" => true}} end

      assert [{@policy, :ok}, {@reporting, {:error, reason}}] =
               Settings.run(spec, get)

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
      assert Settings.labels() == [@policy, @reporting]
    end
  end
end
