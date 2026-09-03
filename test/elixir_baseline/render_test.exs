defmodule ElixirBaseline.RenderTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Render

  @templates [Path.expand("../support/templates", __DIR__)]

  defp repo(projects, settings \\ []) do
    Enum.into(
      settings,
      %{
        name: :r,
        line_length: 80,
        templates: @templates,
        projects: projects,
        tree: MapSet.new()
      }
    )
  end

  defp project(settings \\ []) do
    Enum.into(settings, %{line_length: 80, path: ".", templates: @templates})
  end

  defp template!(dir, path, contents) do
    file = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, contents)
    dir
  end

  describe "files/1" do
    test "keys each project's file by its path in the repo" do
      assert Map.keys(Render.files(repo([project()]))) == [".credo.exs"]
    end

    test "renders each project with its own settings" do
      files =
        Render.files(repo([project(), project(path: "demo", line_length: 120)]))

      assert Enum.sort(Map.keys(files)) == [".credo.exs", "demo/.credo.exs"]
      assert files[".credo.exs"] =~ "line_length: 80"
      assert files["demo/.credo.exs"] =~ "line_length: 120"
    end

    test "generates nothing at the root if no project sits there" do
      files =
        Render.files(
          repo([project(path: "elixir/my_app"), project(path: "elixir/demo")])
        )

      assert Enum.sort(Map.keys(files)) ==
               ["elixir/demo/.credo.exs", "elixir/my_app/.credo.exs"]
    end

    test "formats an Elixir file to the line length it is generated with" do
      contents = Render.files(repo([project(line_length: 120)]))[".credo.exs"]

      assert contents ==
               contents
               |> Code.format_string!(line_length: 120)
               |> IO.iodata_to_binary()
               |> Kernel.<>("\n")
    end

    @tag :tmp_dir
    test "layers a directory over the one before it", %{tmp_dir: dir} do
      template!(
        dir,
        "project/.credo.exs.eex",
        "# line length <%= @line_length %>\n"
      )

      layered = @templates ++ [dir]

      files =
        Render.files(repo([project(templates: layered)], templates: layered))

      assert files[".credo.exs"] == "# line length 80\n"
    end

    @tag :tmp_dir
    test "lets a later directory override a template of a different kind",
         %{tmp_dir: dir} do
      # not an .eex, unlike the one it overrides
      template!(dir, "project/.credo.exs", "mine\n")
      layered = @templates ++ [dir]

      files =
        Render.files(repo([project(templates: layered)], templates: layered))

      assert files == %{".credo.exs" => "mine\n"}
    end

    @tag :tmp_dir
    test "reads only the directories named", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      files = Render.files(repo([project(templates: [dir])], templates: [dir]))

      assert Map.keys(files) == [".tool-versions"]
    end

    @tag :tmp_dir
    test "adds a file an earlier directory does not hold", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      template!(dir, "repo/CODEOWNERS", "* @woylie\n")
      layered = @templates ++ [dir]

      files =
        Render.files(
          repo(
            [
              project(templates: layered),
              project(path: "demo", templates: layered)
            ],
            templates: layered
          )
        )

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
    test "copies a file that is not a template, byte for byte", %{tmp_dir: dir} do
      template!(dir, "repo/.gitignore", "/_build\n<%= not a template %>")

      files = Render.files(repo([project(templates: [dir])], templates: [dir]))

      assert files[".gitignore"] == "/_build\n<%= not a template %>"
    end

    @tag :tmp_dir
    test "generates a repo file once, whatever the projects", %{tmp_dir: dir} do
      template!(dir, "repo/CODEOWNERS", "* @woylie\n")

      files =
        Render.files(
          repo(
            [
              project(path: "a", templates: [dir]),
              project(path: "b", templates: [dir])
            ],
            templates: [dir]
          )
        )

      assert Enum.sort(Map.keys(files)) == ["CODEOWNERS"]
    end

    @tag :tmp_dir
    test "renders a project only from its own template directories",
         %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      layered = @templates ++ [dir]

      files =
        Render.files(
          repo(
            [project(templates: layered), project(path: "demo")],
            templates: layered
          )
        )

      assert Enum.sort(Map.keys(files)) ==
               [".credo.exs", ".tool-versions", "demo/.credo.exs"]
    end

    @tag :tmp_dir
    test "tells a repo template from a project one of the same name",
         %{tmp_dir: dir} do
      template!(dir, "repo/CODEOWNERS", "repo scope\n")
      template!(dir, "project/CODEOWNERS", "project scope\n")

      files =
        Render.files(
          repo([project(templates: [dir])],
            templates: [dir],
            exclude: ["repo/CODEOWNERS"]
          )
        )

      # only the repo one is dropped, though the exclude reaches the project
      assert files == %{"CODEOWNERS" => "project scope\n"}
    end

    @tag :tmp_dir
    test "narrows a scope to what include names", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      template!(dir, "project/.gitattributes", "* text=auto\n")

      files =
        Render.files(
          repo(
            [project(templates: [dir], include: ["project/.gitattributes"])],
            templates: [dir]
          )
        )

      assert Map.keys(files) == [".gitattributes"]
    end

    @tag :tmp_dir
    test "applies exclude after include", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      template!(dir, "project/.gitattributes", "* text=auto\n")

      files =
        Render.files(
          repo(
            [
              project(
                templates: [dir],
                include: ["project/.tool-versions", "project/.gitattributes"],
                exclude: ["project/.gitattributes"]
              )
            ],
            templates: [dir]
          )
        )

      assert Map.keys(files) == [".tool-versions"]
    end

    @tag :tmp_dir
    test "lets a repo name a template only its projects hold", %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")
      excluded = ["project/.tool-versions"]

      # the repo's own scope holds no such template, and that is not a typo
      files =
        Render.files(
          repo([project(templates: [dir], exclude: excluded)],
            templates: [dir],
            exclude: excluded
          )
        )

      assert files == %{}
    end

    @tag :tmp_dir
    test "generates a conditional template only where the file it names is " <>
           "there",
         %{tmp_dir: dir} do
      template!(dir, "repo/hadolint.yaml", "lint\n")

      conditions = %{"repo/hadolint.yaml" => {:exists, "Dockerfile"}}

      spec =
        repo([project(templates: [dir])],
          templates: [dir],
          conditions: conditions
        )

      assert Render.files(spec) == %{}

      assert Render.files(%{spec | tree: MapSet.new(["Dockerfile"])}) ==
               %{"hadolint.yaml" => "lint\n"}
    end

    @tag :tmp_dir
    test "reads a condition on a project template from the repository root",
         %{tmp_dir: dir} do
      template!(dir, "project/.tool-versions", "elixir 1.20\n")

      conditions = %{"project/.tool-versions" => {:exists, ".mise.toml"}}

      spec =
        repo(
          [project(path: "demo", templates: [dir], conditions: conditions)],
          templates: [dir],
          tree: MapSet.new([".mise.toml"])
        )

      assert Map.keys(Render.files(spec)) == ["demo/.tool-versions"]
    end

    test "rejects a selected template that does not exist" do
      for option <- [:include, :exclude] do
        spec = repo([project([{option, ["project/nope"]}])])

        assert_raise ArgumentError, ~r/Unknown template in #{option}/, fn ->
          Render.files(spec)
        end
      end
    end

    test "rejects a condition on a template that does not exist" do
      conditions = %{"project/nope" => {:exists, "Dockerfile"}}

      assert_raise ArgumentError, ~r/Unknown template in conditions/, fn ->
        Render.files(repo([project(conditions: conditions)]))
      end
    end

    test "generates nothing for a scope that includes nothing" do
      assert Render.files(repo([project(include: [])])) == %{}
    end

    @tag :tmp_dir
    test "renders a template with the custom assigns under extra",
         %{tmp_dir: dir} do
      template!(dir, "project/Dockerfile.eex", "FROM <%= @extra[:image] %>\n")

      files =
        Render.files(
          repo([project(templates: [dir], extra: [image: "elixir:1.20"])],
            templates: [dir]
          )
        )

      assert files["Dockerfile"] == "FROM elixir:1.20\n"
    end

    @tag :tmp_dir
    test "generates no file if a template renders to nothing",
         %{tmp_dir: dir} do
      template!(
        dir,
        "project/assets.exs.eex",
        "<%= if @extra[:assets] do %>x<% end %>"
      )

      files = Render.files(repo([project(templates: [dir])], templates: [dir]))

      assert files == %{}

      with_assets =
        Render.files(
          repo([project(templates: [dir], extra: [assets: true])],
            templates: [dir]
          )
        )

      assert Map.keys(with_assets) == ["assets.exs"]
    end

    @tag :tmp_dir
    test "copies an empty file that is not a template", %{tmp_dir: dir} do
      template!(dir, "repo/.keep", "")

      files = Render.files(repo([project(templates: [dir])], templates: [dir]))

      assert files == %{".keep" => ""}
    end

    @tag :tmp_dir
    test "renders a template using extra when none is set", %{tmp_dir: dir} do
      template!(dir, "project/Dockerfile.eex", "FROM <%= @extra[:image] %>\n")

      files = Render.files(repo([project(templates: [dir])], templates: [dir]))

      assert files["Dockerfile"] == "FROM \n"
    end
  end
end
