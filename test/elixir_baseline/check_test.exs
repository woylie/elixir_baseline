defmodule ElixirBaseline.CheckTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check
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

  defp stub(contents) do
    fn path ->
      assert path == "repos/acme/spek/contents/.credo.exs"
      {:ok, %{"content" => Base.encode64(contents)}}
    end
  end

  defp stub_all(by_path) do
    fn "repos/acme/spek/contents/" <> path ->
      case Map.fetch(by_path, path) do
        {:ok, contents} -> {:ok, %{"content" => Base.encode64(contents)}}
        :error -> {:error, {:http, 404, "Not Found"}}
      end
    end
  end

  describe "run/2" do
    test "is ok when the file matches" do
      assert Check.run(@spek, stub(rendered(@spek, ".credo.exs"))) ==
               [{".credo.exs", :ok}]
    end

    test "is ok when only the final newline differs" do
      trimmed = @spek |> rendered(".credo.exs") |> String.trim_trailing()

      assert Check.run(@spek, stub(trimmed)) == [{".credo.exs", :ok}]
    end

    test "holds the difference when the file differs" do
      changed =
        @spek
        |> rendered(".credo.exs")
        |> String.replace("line_length: 80", "line_length: 120")

      assert [{".credo.exs", {:differs, diff}}] =
               Check.run(@spek, stub(changed))

      assert ElixirBaseline.Diff.counts(diff) == {1, 1}
    end

    test "holds what the template renders when the file does not exist" do
      fetcher = fn _ -> {:error, {:http, 404, "Not Found"}} end

      assert [{".credo.exs", {:missing, expected}}] = Check.run(@spek, fetcher)
      assert expected == rendered(@spek, ".credo.exs")
    end

    test "reports a failed request as an error, not as drift" do
      fetcher = fn _ -> {:error, {:http, 403, "Forbidden"}} end

      assert [{".credo.exs", {:error, _}}] = Check.run(@spek, fetcher)
    end

    test "reports a finding per file, ordered by path" do
      fetcher =
        stub_all(%{
          ".credo.exs" => rendered(@nested, ".credo.exs"),
          "demo/.credo.exs" => rendered(@nested, "demo/.credo.exs")
        })

      assert Check.run(@nested, fetcher) ==
               [{".credo.exs", :ok}, {"demo/.credo.exs", :ok}]
    end

    test "reports a project that has drifted on its own" do
      fetcher = stub_all(%{".credo.exs" => rendered(@nested, ".credo.exs")})

      assert [{".credo.exs", :ok}, {"demo/.credo.exs", {:missing, _}}] =
               Check.run(@nested, fetcher)
    end

    test "is ok when a workflow is pinned newer than the template" do
      bumped = @workflow |> rendered(@ci) |> String.replace(@pin, @newer)

      fetcher =
        stub_all(%{@ci => bumped, @action => rendered(@workflow, @action)})

      assert {@ci, :ok} in Check.run(@workflow, fetcher)
    end

    test "is ok when a workflow is pinned to a tag rather than a digest" do
      unpinned =
        @workflow |> rendered(@ci) |> String.replace(@pin, "v7")

      fetcher =
        stub_all(%{@ci => unpinned, @action => rendered(@workflow, @action)})

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
        stub_all(%{@ci => changed, @action => rendered(@workflow, @action)})

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
        stub_all(%{@ci => rendered(@workflow, @ci), @action => bumped})

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
