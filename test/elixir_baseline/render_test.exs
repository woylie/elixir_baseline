defmodule ElixirBaseline.RenderTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Render

  defp repo(projects, settings \\ []) do
    Enum.into(settings, %{name: :r, line_length: 80, projects: projects})
  end

  defp project(settings \\ []) do
    Enum.into(settings, %{line_length: 80, path: "."})
  end

  defp template!(dir, path, contents) do
    file = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, contents)
    dir
  end

  describe "files/1" do
    test "keys each project's file by its path in the repo" do
      files = Render.files(repo([%{line_length: 80, path: "."}]))

      assert Map.keys(files) == [".credo.exs"]
    end

    test "renders each project with its own settings" do
      files =
        Render.files(
          repo([
            %{line_length: 80, path: "."},
            %{line_length: 120, path: "demo"}
          ])
        )

      assert Enum.sort(Map.keys(files)) == [".credo.exs", "demo/.credo.exs"]
      assert files[".credo.exs"] =~ "max_length: 80"
      assert files["demo/.credo.exs"] =~ "max_length: 120"
    end

    test "generates nothing at the root where no project sits there" do
      files =
        Render.files(
          repo([
            %{line_length: 80, path: "elixir/my_app"},
            %{line_length: 80, path: "elixir/my_app/demo"}
          ])
        )

      assert Enum.sort(Map.keys(files)) ==
               ["elixir/my_app/.credo.exs", "elixir/my_app/demo/.credo.exs"]
    end

    @tag :tmp_dir
    test "layers a configured directory over the package's own",
         %{tmp_dir: dir} do
      template!(
        dir,
        "project/.credo.exs.eex",
        "# line length <%= @line_length %>\n"
      )

      files =
        [project(templates: [:default, dir])]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert files[".credo.exs"] == "# line length 80\n"
    end

    @tag :tmp_dir
    test "adds a file the package's own directory does not hold",
         %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      template!(dir, "repo/CODEOWNERS", "* @woylie\n")

      files =
        [
          project(templates: [:default, dir]),
          project(path: "demo", templates: [:default, dir])
        ]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert Enum.sort(Map.keys(files)) ==
               [
                 ".credo.exs",
                 ".tool-versions",
                 "CODEOWNERS",
                 "demo/.credo.exs",
                 "demo/.tool-versions"
               ]
    end

    @tag :tmp_dir
    test "copies a file that is not a template, byte for byte",
         %{tmp_dir: dir} do
      template!(dir, "repo/.gitignore", "/_build\n/deps\n<%= not a template %>")

      files =
        [project()]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert files[".gitignore"] == "/_build\n/deps\n<%= not a template %>"
    end

    @tag :tmp_dir
    test "generates a repo file once, whatever the projects", %{tmp_dir: dir} do
      template!(dir, "repo/CODEOWNERS", "* @woylie\n")

      files =
        [project(path: "a"), project(path: "b")]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert files["CODEOWNERS"] == "* @woylie\n"

      assert Enum.sort(Map.keys(files)) ==
               ["CODEOWNERS", "a/.credo.exs", "b/.credo.exs"]
    end

    @tag :tmp_dir
    test "renders a project only from its own template directories",
         %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      files =
        [project(templates: [:default, dir]), project(path: "demo")]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert Enum.sort(Map.keys(files)) ==
               [".credo.exs", ".tool-versions", "demo/.credo.exs"]
    end

    @tag :tmp_dir
    test "excludes a path from the scope it is written on", %{tmp_dir: dir} do
      template!(dir, "repo/CODEOWNERS", "* @woylie\n")

      files =
        [
          project(exclude: ["project/.credo.exs"]),
          project(path: "demo")
        ]
        |> repo(templates: [:default, dir], exclude: ["repo/CODEOWNERS"])
        |> Render.files()

      assert Map.keys(files) == ["demo/.credo.exs"]
    end

    @tag :tmp_dir
    test "narrows a scope to what include names", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      template!(dir, "project/.gitattributes", "* text=auto\n")

      files =
        [
          project(
            templates: [:default, dir],
            include: ["project/.credo.exs", "project/.gitattributes"]
          )
        ]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert Enum.sort(Map.keys(files)) == [".credo.exs", ".gitattributes"]
    end

    @tag :tmp_dir
    test "applies exclude after include", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      files =
        [
          project(
            templates: [:default, dir],
            include: ["project/.credo.exs", "project/.tool-versions"],
            exclude: ["project/.credo.exs"]
          )
        ]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert Map.keys(files) == [".tool-versions"]
    end

    @tag :tmp_dir
    test "tells a repo template from a project one of the same name",
         %{tmp_dir: dir} do
      template!(dir, "repo/CODEOWNERS", "repo scope\n")
      template!(dir, "project/CODEOWNERS", "project scope\n")

      files =
        [project(templates: [:default, dir], exclude: ["project/.credo.exs"])]
        |> repo(templates: [:default, dir], exclude: ["repo/CODEOWNERS"])
        |> Render.files()

      # only the repo one is dropped, though the exclude reaches the project
      assert files == %{"CODEOWNERS" => "project scope\n"}
    end

    test "rejects a selected template that does not exist" do
      for option <- [:include, :exclude] do
        repo = repo([project([{option, ["project/.credo.exs.eex"]}])])

        assert_raise ArgumentError, ~r/Unknown template in #{option}/, fn ->
          Render.files(repo)
        end
      end
    end

    @tag :tmp_dir
    test "lets a repo name a template only its projects hold", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      # the repo's own scope holds no such template, and that is not a typo
      files =
        [
          project(
            templates: [:default, dir],
            exclude: ["project/.tool-versions"]
          )
        ]
        |> repo(templates: [:default, dir], exclude: ["project/.tool-versions"])
        |> Render.files()

      assert Map.keys(files) == [".credo.exs"]
    end

    @tag :tmp_dir
    test "lets a later directory override a template of a different kind",
         %{tmp_dir: dir} do
      # not an .eex, where the one it overrides is
      template!(dir, "project/.credo.exs", "mine\n")

      files =
        [project(templates: [:default, dir])]
        |> repo(templates: [:default, dir])
        |> Render.files()

      assert files == %{".credo.exs" => "mine\n"}
    end

    @tag :tmp_dir
    test "reads only the directories named, not the defaults too",
         %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      files =
        [project(templates: [dir])]
        |> repo(templates: [dir])
        |> Render.files()

      assert Map.keys(files) == [".tool-versions"]
    end

    test "generates nothing for a scope that includes nothing" do
      files = Render.files(repo([project(include: [])]))

      assert files == %{}
    end

    test "formats an Elixir file to the line length it is generated with" do
      contents =
        Render.files(repo([%{line_length: 120, path: "."}]))[".credo.exs"]

      assert contents ==
               contents
               |> Code.format_string!(line_length: 120)
               |> IO.iodata_to_binary()
               |> Kernel.<>("\n")
    end
  end
end
