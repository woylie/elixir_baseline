defmodule ElixirBaseline.RenderTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Render

  describe "credo/1" do
    test "uses line_length for MaxLineLength and for formatting the output" do
      rendered = Render.credo(%{line_length: 120})

      assert rendered =~ "max_length: 120"

      assert rendered ==
               rendered
               |> Code.format_string!(line_length: 120)
               |> IO.iodata_to_binary()
               |> Kernel.<>("\n")
    end
  end

  describe "files/1" do
    test "keys the repo's file by its path in the repo" do
      spec = %{line_length: 80, path: ".", subprojects: []}

      assert Map.keys(Render.files(spec)) == [".credo.exs"]
    end

    test "puts a subproject's file under its path, with its own settings" do
      spec = %{
        line_length: 80,
        path: ".",
        subprojects: [%{line_length: 120, path: "demo"}]
      }

      files = Render.files(spec)

      assert Enum.sort(Map.keys(files)) == [".credo.exs", "demo/.credo.exs"]
      assert files[".credo.exs"] =~ "max_length: 80"
      assert files["demo/.credo.exs"] =~ "max_length: 120"
    end

    test "generates nothing at the root for a repo with a path" do
      spec = %{
        line_length: 80,
        path: "elixir/my_app",
        subprojects: [%{line_length: 80, path: "elixir/my_app/demo"}]
      }

      assert Enum.sort(Map.keys(Render.files(spec))) ==
               ["elixir/my_app/.credo.exs", "elixir/my_app/demo/.credo.exs"]
    end
  end
end
