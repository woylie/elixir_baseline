defmodule ElixirBaseline.PatchTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Patch

  @patches [{:line_length, 80}]

  defp patch(source), do: Patch.apply(@patches, source)

  describe "files/1" do
    test "names one formatter config per project" do
      repo = %{
        projects: [
          %{path: ".", line_length: 80},
          %{path: "demo", line_length: 120}
        ]
      }

      assert Patch.files(repo) == %{
               ".formatter.exs" => [{:line_length, 80}],
               "demo/.formatter.exs" => [{:line_length, 120}]
             }
    end
  end

  describe "apply/2" do
    test "replaces the value and leaves the rest of the file alone" do
      source = """
      # The house style.
      [
        import_deps: [:ecto],
        plugins: [Phoenix.LiveView.HTMLFormatter],
        # keep this
        line_length: 98,
        inputs: ["{mix,.formatter}.exs"]
      ]
      """

      assert {:ok, patched} = patch(source)

      assert patched ==
               String.replace(source, "line_length: 98", "line_length: 80")
    end

    test "returns the file unchanged when the value already matches" do
      source = "[inputs: [\"mix.exs\"], line_length: 80]\n"

      assert patch(source) == {:ok, source}
    end

    test "adds the setting after the last one when it is absent" do
      source = """
      [
        import_deps: [:ecto],
        inputs: ["mix.exs"]
      ]
      """

      assert {:ok, patched} = patch(source)

      assert patched == """
             [
               import_deps: [:ecto],
               inputs: ["mix.exs"],
               line_length: 80
             ]
             """
    end

    test "reads only the top-level setting" do
      source = """
      [
        nested: [line_length: 120],
        line_length: 98
      ]
      """

      assert {:ok, patched} = patch(source)
      assert patched =~ "nested: [line_length: 120]"
      assert patched =~ "\n  line_length: 80"
    end

    test "does not take a commented-out setting for the real one" do
      source = """
      [
        # line_length: 98
        inputs: ["mix.exs"]
      ]
      """

      assert {:ok, patched} = patch(source)
      assert patched =~ "# line_length: 98"
      assert patched =~ "line_length: 80"
    end

    test "applies every patch in order" do
      source = "[inputs: [\"mix.exs\"]]\n"

      assert {:ok, patched} =
               Patch.apply([{:line_length, 98}, {:line_length, 80}], source)

      assert patched == "[inputs: [\"mix.exs\"], line_length: 80]\n"
    end

    test "reports a file that does not parse" do
      assert {:error, reason} = patch("[\n  inputs: [\n")
      assert reason =~ "does not parse"
    end

    test "patches the list a file with bindings above it ends in" do
      source = """
      locals_without_parens = [allow: 1, deny: 1]

      [
        inputs: ["{mix,.formatter}.exs"],
        line_length: 98,
        locals_without_parens: locals_without_parens
      ]
      """

      assert {:ok, patched} = patch(source)

      assert patched ==
               String.replace(source, "line_length: 98", "line_length: 80")
    end

    test "reports a file that does not end in a settings list" do
      assert {:error, reason} = patch("System.halt()\n")
      assert reason =~ "does not end in a settings list"
    end

    test "reports an empty settings list rather than guessing where to write" do
      assert {:error, reason} = patch("[]\n")
      assert reason =~ "empty"
    end

    test "refuses a patch whose result does not hold what it asked for" do
      assert {:error, reason} =
               Patch.apply([{:line_length, "80"}], "[line_length: 98]\n")

      assert reason =~ "did not take"
    end

    test "refuses a value it cannot read rather than adding a second one" do
      assert {:error, reason} = patch("[line_length: @length]\n")
      assert reason =~ "not a literal integer"
    end

    test "never evaluates the file" do
      source = """
      [
        inputs: [Path.wildcard("*.ex")],
        plugins: [NotLoaded.Formatter],
        line_length: 98
      ]
      """

      assert {:ok, patched} = patch(source)
      assert patched =~ "line_length: 80"
    end
  end
end
