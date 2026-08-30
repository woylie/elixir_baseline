defmodule ElixirBaseline.CheckTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check
  alias ElixirBaseline.Patch
  alias ElixirBaseline.Render

  @templates [Path.expand("../support/templates", __DIR__)]
  @workflows [Path.expand("../support/workflow_templates", __DIR__)]

  @project %{
    name: :spek,
    owner: "acme",
    templates: @templates,
    line_length: 80,
    path: ".",
    projects: []
  }

  @root %{@project | line_length: 80, path: "."}
  @demo %{@project | line_length: 120, path: "demo"}

  @spek %{@project | projects: [@root]}
  @nested %{@spek | projects: [@root, @demo]}
  @workflow %{@project | templates: @workflows}

  @ci ".github/workflows/ci.yaml"
  @action ".github/actions/setup/action.yaml"
  @pin "3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
  @newer "c2b5f1a0e4d3927f6a8b1c0d5e4f3a2b1c0d9e8f # v7.1.0"

  defp rendered(spec, path), do: spec |> Render.files() |> Map.fetch!(path)

  defp formatter(length) do
    """
    [
      inputs: ["{mix,.formatter}.exs"],
      line_length: #{length}
    ]
    """
  end

  defp formatters(spec) do
    Map.new(Patch.files(spec), fn {path, [{:line_length, length}]} ->
      {path, formatter(length)}
    end)
  end

  defp stub(spec, contents), do: stub_all(spec, %{".credo.exs" => contents})

  defp stub_all(spec, by_path) do
    files = Map.merge(formatters(spec), by_path)

    fn "repos/acme/spek/contents/" <> path ->
      case Map.fetch(files, path) do
        {:ok, contents} -> {:ok, %{"content" => Base.encode64(contents)}}
        :error -> {:error, {:http, 404, "Not Found"}}
      end
    end
  end

  describe "run/2" do
    test "is ok when the file matches" do
      fetcher = stub(@spek, rendered(@spek, ".credo.exs"))

      assert Check.run(@spek, fetcher) ==
               [{".credo.exs", :ok}, {".formatter.exs", :ok}]
    end

    test "is ok when only the final newline differs" do
      trimmed = @spek |> rendered(".credo.exs") |> String.trim_trailing()

      assert {".credo.exs", :ok} in Check.run(@spek, stub(@spek, trimmed))
    end

    test "holds the difference when the file differs" do
      changed =
        @spek
        |> rendered(".credo.exs")
        |> String.replace("line_length: 80", "line_length: 120")

      assert [{".credo.exs", {:differs, diff}}, {".formatter.exs", :ok}] =
               Check.run(@spek, stub(@spek, changed))

      assert ElixirBaseline.Diff.counts(diff) == {1, 1}
    end

    test "holds what the template renders when the file does not exist" do
      fetcher = fn _ -> {:error, {:http, 404, "Not Found"}} end

      assert [{".credo.exs", {:missing, expected}} | _rest] =
               Check.run(@spek, fetcher)

      assert expected == rendered(@spek, ".credo.exs")
    end

    test "reports a failed request as an error, not as drift" do
      fetcher = fn _ -> {:error, {:http, 403, "Forbidden"}} end

      assert [{".credo.exs", {:error, _}} | _rest] = Check.run(@spek, fetcher)
    end

    test "reports a finding per file, ordered by path" do
      fetcher =
        stub_all(@nested, %{
          ".credo.exs" => rendered(@nested, ".credo.exs"),
          "demo/.credo.exs" => rendered(@nested, "demo/.credo.exs")
        })

      assert Check.run(@nested, fetcher) ==
               [
                 {".credo.exs", :ok},
                 {".formatter.exs", :ok},
                 {"demo/.credo.exs", :ok},
                 {"demo/.formatter.exs", :ok}
               ]
    end

    test "reports a project that has drifted on its own" do
      fetcher =
        stub_all(@nested, %{".credo.exs" => rendered(@nested, ".credo.exs")})

      assert [
               {".credo.exs", :ok},
               {".formatter.exs", :ok},
               {"demo/.credo.exs", {:missing, _}},
               {"demo/.formatter.exs", :ok}
             ] = Check.run(@nested, fetcher)
    end

    test "reports a patched file whose setting differs" do
      fetcher = stub_all(@spek, %{".formatter.exs" => formatter(120)})

      assert {".formatter.exs", {:differs, diff}} =
               Enum.find(
                 Check.run(@spek, fetcher),
                 &match?({_, {:differs, _}}, &1)
               )

      assert ElixirBaseline.Diff.counts(diff) == {1, 1}
    end

    test "is ok when a patched file already holds the setting" do
      fetcher = stub_all(@spek, %{".formatter.exs" => formatter(80)})

      assert {".formatter.exs", :ok} in Check.run(@spek, fetcher)
    end

    test "reports a patched file it cannot parse as unpatchable" do
      fetcher = stub_all(@spek, %{".formatter.exs" => "[\n"})

      assert {".formatter.exs", {:unpatchable, _}} =
               Enum.find(
                 Check.run(@spek, fetcher),
                 &match?({_, {:unpatchable, _}}, &1)
               )
    end

    test "reports a patched file that does not exist as unpatchable" do
      fetcher = fn _ -> {:error, {:http, 404, "Not Found"}} end

      assert [_credo, {".formatter.exs", {:unpatchable, reason}}] =
               Check.run(@spek, fetcher)

      assert reason == "there is no file to patch"
    end

    test "is ok when a workflow is pinned newer than the template" do
      bumped = @workflow |> rendered(@ci) |> String.replace(@pin, @newer)

      fetcher =
        stub_all(@workflow, %{
          @ci => bumped,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, :ok} in Check.run(@workflow, fetcher)
    end

    test "is ok when a workflow is pinned to a tag rather than a digest" do
      unpinned =
        @workflow |> rendered(@ci) |> String.replace(@pin, "v7")

      fetcher =
        stub_all(@workflow, %{
          @ci => unpinned,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, :ok} in Check.run(@workflow, fetcher)
    end

    test "reports a workflow that differs in a step, pins included" do
      changed =
        @workflow
        |> rendered(@ci)
        |> String.replace(@pin, @newer)
        |> String.replace(
          "persist-credentials: false",
          "persist-credentials: true"
        )

      fetcher =
        stub_all(@workflow, %{
          @ci => changed,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, {:differs, diff}} =
               Enum.find(Check.run(@workflow, fetcher), &match?({@ci, _}, &1))

      assert ElixirBaseline.Diff.counts(diff) == {2, 2}
    end

    test "reports a pin outside .github/workflows as drift" do
      bumped =
        @workflow
        |> rendered(@action)
        |> String.replace("5304e04ea2b355f03681464e683d92e3b2f18451", "aaaa111")

      fetcher =
        stub_all(@workflow, %{
          @ci => rendered(@workflow, @ci),
          @action => bumped
        })

      assert {@action, {:differs, _}} =
               Enum.find(
                 Check.run(@workflow, fetcher),
                 &match?({@action, _}, &1)
               )
    end
  end

  describe "ok?/1" do
    test "is true only when every file matches" do
      assert Check.ok?([{".credo.exs", :ok}, {"demo/.credo.exs", :ok}])

      refute Check.ok?([
               {".credo.exs", :ok},
               {"demo/.credo.exs", {:missing, ""}}
             ])
    end
  end
end
