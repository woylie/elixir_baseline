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
      assert Map.keys(Render.files(%{line_length: 80})) == [".credo.exs"]
    end
  end
end
