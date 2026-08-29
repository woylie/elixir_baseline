defmodule ElixirBaseline.RenderTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Render

  defp repo(projects), do: %{line_length: 80, projects: projects}

  describe "files/1" do
    test "keys each project's file by its path in the repo" do
      files = Render.files(repo([%{line_length: 80, path: "."}]))

      assert Map.keys(files) == [".credo.exs"]
    end

    test "renders each project with its own settings" do
      files =
        repo([
          %{line_length: 80, path: "."},
          %{line_length: 120, path: "demo"}
        ])
        |> Render.files()

      assert Enum.sort(Map.keys(files)) == [".credo.exs", "demo/.credo.exs"]
      assert files[".credo.exs"] =~ "max_length: 80"
      assert files["demo/.credo.exs"] =~ "max_length: 120"
    end

    test "generates nothing at the root where no project sits there" do
      files =
        repo([
          %{line_length: 80, path: "elixir/my_app"},
          %{line_length: 80, path: "elixir/my_app/demo"}
        ])
        |> Render.files()

      assert Enum.sort(Map.keys(files)) ==
               ["elixir/my_app/.credo.exs", "elixir/my_app/demo/.credo.exs"]
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
