defmodule ElixirBaseline.CheckTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check
  alias ElixirBaseline.Render

  @spek %{
    name: :spek,
    owner: "acme",
    line_length: 80,
    path: ".",
    subprojects: []
  }

  @nested %{
    @spek
    | subprojects: [
        %{name: :spek, owner: "acme", line_length: 120, path: "demo"}
      ]
  }

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
      assert Check.run(@spek, stub(Render.credo(@spek))) == [
               {".credo.exs", :ok}
             ]
    end

    test "is ok when only the final newline differs" do
      trimmed = @spek |> Render.credo() |> String.trim_trailing()

      assert Check.run(@spek, stub(trimmed)) == [{".credo.exs", :ok}]
    end

    test "reports a magnitude when the file differs" do
      changed =
        @spek
        |> Render.credo()
        |> String.replace("max_length: 80", "max_length: 120")

      assert [{".credo.exs", {:differs, 2}}] = Check.run(@spek, stub(changed))
    end

    test "is missing when the file does not exist" do
      fetcher = fn _ -> {:error, {:http, 404, "Not Found"}} end

      assert Check.run(@spek, fetcher) == [{".credo.exs", :missing}]
    end

    test "reports a failed request as an error, not as drift" do
      fetcher = fn _ -> {:error, {:http, 403, "Forbidden"}} end

      assert [{".credo.exs", {:error, _}}] = Check.run(@spek, fetcher)
    end

    test "reports a finding per file, ordered by path" do
      [subproject] = @nested.subprojects

      fetcher =
        stub_all(%{
          ".credo.exs" => Render.credo(@nested),
          "demo/.credo.exs" => Render.credo(subproject)
        })

      assert Check.run(@nested, fetcher) ==
               [{".credo.exs", :ok}, {"demo/.credo.exs", :ok}]
    end

    test "reports a subproject that has drifted on its own" do
      fetcher = stub_all(%{".credo.exs" => Render.credo(@nested)})

      assert [{".credo.exs", :ok}, {"demo/.credo.exs", :missing}] =
               Check.run(@nested, fetcher)
    end
  end

  describe "ok?/1" do
    test "is true only when every file matches" do
      assert Check.ok?([{".credo.exs", :ok}, {"demo/.credo.exs", :ok}])
      refute Check.ok?([{".credo.exs", :ok}, {"demo/.credo.exs", :missing}])
    end
  end
end
