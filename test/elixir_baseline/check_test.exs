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
    projects: [],
    tree: MapSet.new()
  }

  @root %{@project | line_length: 80, path: "."}
  @demo %{@project | line_length: 120, path: "demo"}

  @spek %{@project | projects: [@root]}
  @nested %{@spek | projects: [@root, @demo]}
  @workflow %{@project | templates: @workflows}

  @seeds [Path.expand("../support/seed_templates", __DIR__)]
  @seed ["project/.sobelow-conf"]

  @ci ".github/workflows/ci.yaml"
  @action ".github/actions/setup/action.yaml"
  @pin "3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
  @newer "c2b5f1a0e4d3927f6a8b1c0d5e4f3a2b1c0d9e8f # v7.1.0"

  defp rendered(spec, path) do
    spec |> Render.files() |> Map.merge(Render.seeds(spec)) |> Map.fetch!(path)
  end

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

  defp tree(spec, paths), do: %{spec | tree: MapSet.new(paths)}

  defp seeded do
    project = Map.merge(@project, %{templates: @seeds, seed: @seed})

    %{project | projects: [project]}
  end

  defp unread, do: fn path -> flunk("read #{path}") end

  defp stub(spec, contents), do: stub_all(spec, %{".credo.exs" => contents})

  # The stubbed files are the repo's tree, so a read of a path the tree does
  # not hold fails rather than answering 404.
  defp stub_all(spec, by_path) do
    files = Map.merge(formatters(spec), by_path)

    fetcher = fn "repos/acme/spek/contents/" <> path ->
      {:ok, %{"content" => Base.encode64(Map.fetch!(files, path))}}
    end

    {tree(spec, Map.keys(files)), fetcher}
  end

  describe "run/2" do
    test "is ok when the file matches" do
      {spek, fetcher} = stub(@spek, rendered(@spek, ".credo.exs"))

      assert Check.run(spek, fetcher) ==
               [{".credo.exs", :ok}, {".formatter.exs", :ok}]
    end

    test "is ok when only the final newline differs" do
      trimmed = @spek |> rendered(".credo.exs") |> String.trim_trailing()
      {spek, fetcher} = stub(@spek, trimmed)

      assert {".credo.exs", :ok} in Check.run(spek, fetcher)
    end

    test "holds the difference when the file differs" do
      changed =
        @spek
        |> rendered(".credo.exs")
        |> String.replace("line_length: 80", "line_length: 120")

      {spek, fetcher} = stub(@spek, changed)

      assert [{".credo.exs", {:differs, diff}}, {".formatter.exs", :ok}] =
               Check.run(spek, fetcher)

      assert ElixirBaseline.Diff.counts(diff) == {1, 1}
    end

    test "holds what the template renders when the file does not exist" do
      assert [{".credo.exs", {:missing, expected}} | _rest] =
               Check.run(tree(@spek, []), unread())

      assert expected == rendered(@spek, ".credo.exs")
    end

    test "reports a failed request as an error, not as drift" do
      spek = tree(@spek, [".credo.exs"])
      fetcher = fn _ -> {:error, {:http, 403, "Forbidden"}} end

      assert [{".credo.exs", {:error, _}} | _rest] = Check.run(spek, fetcher)
    end

    test "reports a repo that could not be resolved as an error per file" do
      spek = Map.put(@spek, :error, "Not Found")

      assert Check.run(spek, unread()) ==
               [
                 {".credo.exs", {:error, "Not Found"}},
                 {".formatter.exs", {:error, "Not Found"}}
               ]
    end

    test "reports a finding per file, ordered by path" do
      {nested, fetcher} =
        stub_all(@nested, %{
          ".credo.exs" => rendered(@nested, ".credo.exs"),
          "demo/.credo.exs" => rendered(@nested, "demo/.credo.exs")
        })

      assert Check.run(nested, fetcher) ==
               [
                 {".credo.exs", :ok},
                 {".formatter.exs", :ok},
                 {"demo/.credo.exs", :ok},
                 {"demo/.formatter.exs", :ok}
               ]
    end

    test "reports a project that has drifted on its own" do
      {nested, fetcher} =
        stub_all(@nested, %{".credo.exs" => rendered(@nested, ".credo.exs")})

      assert [
               {".credo.exs", :ok},
               {".formatter.exs", :ok},
               {"demo/.credo.exs", {:missing, _}},
               {"demo/.formatter.exs", :ok}
             ] = Check.run(nested, fetcher)
    end

    test "is ok when a seeded file is there, without reading it" do
      {spec, fetcher} = stub_all(seeded(), %{})
      spec = tree(spec, [".formatter.exs", ".sobelow-conf"])

      guarded = fn
        "repos/acme/spek/contents/.sobelow-conf" -> flunk("read the seed")
        path -> fetcher.(path)
      end

      assert {".sobelow-conf", :ok} in Check.run(spec, guarded)
    end

    test "holds what a missing seeded file would start from" do
      seeded = seeded()

      findings = Check.run(tree(seeded, []), unread())

      assert {".sobelow-conf", {:missing, expected}} =
               Enum.find(findings, &match?({".sobelow-conf", _}, &1))

      assert expected == rendered(seeded, ".sobelow-conf")
    end

    test "reports a patched file whose setting differs" do
      {spek, fetcher} = stub_all(@spek, %{".formatter.exs" => formatter(120)})

      assert {".formatter.exs", {:differs, diff}} =
               Enum.find(
                 Check.run(spek, fetcher),
                 &match?({_, {:differs, _}}, &1)
               )

      assert ElixirBaseline.Diff.counts(diff) == {1, 1}
    end

    test "is ok when a patched file already holds the setting" do
      {spek, fetcher} = stub_all(@spek, %{".formatter.exs" => formatter(80)})

      assert {".formatter.exs", :ok} in Check.run(spek, fetcher)
    end

    test "reports a patched file it cannot parse as unpatchable" do
      {spek, fetcher} = stub_all(@spek, %{".formatter.exs" => "[\n"})

      assert {".formatter.exs", {:unpatchable, _}} =
               Enum.find(
                 Check.run(spek, fetcher),
                 &match?({_, {:unpatchable, _}}, &1)
               )
    end

    test "reports a patched file that does not exist as unpatchable" do
      assert [_credo, {".formatter.exs", {:unpatchable, reason}}] =
               Check.run(tree(@spek, []), unread())

      assert reason == "there is no file to patch"
    end

    test "is ok when a workflow is pinned newer than the template" do
      bumped = @workflow |> rendered(@ci) |> String.replace(@pin, @newer)

      {workflow, fetcher} =
        stub_all(@workflow, %{
          @ci => bumped,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, :ok} in Check.run(workflow, fetcher)
    end

    test "is ok when a workflow is pinned to a tag rather than a digest" do
      unpinned =
        @workflow |> rendered(@ci) |> String.replace(@pin, "v7")

      {workflow, fetcher} =
        stub_all(@workflow, %{
          @ci => unpinned,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, :ok} in Check.run(workflow, fetcher)
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

      {workflow, fetcher} =
        stub_all(@workflow, %{
          @ci => changed,
          @action => rendered(@workflow, @action)
        })

      assert {@ci, {:differs, diff}} =
               Enum.find(Check.run(workflow, fetcher), &match?({@ci, _}, &1))

      assert ElixirBaseline.Diff.counts(diff) == {2, 2}
    end

    test "reports a pin outside .github/workflows as drift" do
      bumped =
        @workflow
        |> rendered(@action)
        |> String.replace("5304e04ea2b355f03681464e683d92e3b2f18451", "aaaa111")

      {workflow, fetcher} =
        stub_all(@workflow, %{
          @ci => rendered(@workflow, @ci),
          @action => bumped
        })

      assert {@action, {:differs, _}} =
               Enum.find(
                 Check.run(workflow, fetcher),
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
