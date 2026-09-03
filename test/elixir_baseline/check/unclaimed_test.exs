defmodule ElixirBaseline.Check.UnclaimedTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check.Unclaimed

  @templates [Path.expand("../../support/templates", __DIR__)]

  defp repo(paths, projects \\ ["."], templates \\ @templates) do
    %{
      name: :spek,
      owner: "acme",
      line_length: 80,
      templates: templates,
      projects: for(path <- projects, do: project(path, templates)),
      tree: MapSet.new(paths)
    }
  end

  defp project(path, templates) do
    %{name: :spek, line_length: 80, templates: templates, path: path}
  end

  defp template!(dir, path, contents) do
    file = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, contents)
    dir
  end

  describe "run/1" do
    test "finds nothing when every project is claimed" do
      repo = repo(["mix.exs", ".credo.exs", "demo/mix.exs"], [".", "demo"])

      assert Unclaimed.run(repo) == []
    end

    test "reports a mix.exs no project claims" do
      repo = repo(["mix.exs", "demo/mix.exs"])

      assert [{"demo/mix.exs", {:drift, "unclaimed", remedy}}] =
               Unclaimed.run(repo)

      assert remedy == ~s(add a project with path: "demo")
    end

    test "reports a generated file no project claims" do
      repo = repo(["mix.exs", "demo/.credo.exs"])

      assert [{"demo/.credo.exs", {:drift, "unclaimed", _}}] =
               Unclaimed.run(repo)
    end

    test "reports the repository root when no project sits there" do
      repo = repo(["mix.exs", "demo/mix.exs"], ["demo"])

      assert [{"mix.exs", {:drift, "unclaimed", remedy}}] = Unclaimed.run(repo)
      assert remedy =~ "repository root"
    end

    test "reports every unclaimed file, ordered by path" do
      repo = repo(["demo/.credo.exs", "demo/mix.exs", "mix.exs"], ["."])

      assert [{"demo/.credo.exs", _}, {"demo/mix.exs", _}] =
               Unclaimed.run(repo)
    end

    test "ignores a file no template generates" do
      assert Unclaimed.run(repo(["demo/README.md", "demo/credo.exs"])) == []
    end

    @tag :tmp_dir
    test "matches a template that sits in a directory of its own",
         %{tmp_dir: dir} do
      template!(dir, "project/test/support/factory.ex", "defmodule F do\nend\n")

      paths = ["mix.exs", "demo/test/support/factory.ex"]

      assert [{"demo/test/support/factory.ex", _}] =
               Unclaimed.run(repo(paths, ["."], [dir]))
    end

    test "returns nothing for a repo that could not be resolved" do
      repo = Map.put(repo(["demo/mix.exs"]), :error, "Not Found")

      assert Unclaimed.run(repo) == []
    end
  end

  describe "ok?/1" do
    test "is true only when nothing is unclaimed" do
      assert Unclaimed.ok?([])
      refute Unclaimed.ok?([{"demo/mix.exs", {:drift, "unclaimed", "x"}}])
    end
  end
end
