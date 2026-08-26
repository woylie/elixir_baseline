defmodule ElixirBaseline.Check.CredoTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Check.Credo
  alias ElixirBaseline.Render

  @spek %{name: :spek, owner: "acme", line_length: 80}

  defp stub(contents) do
    fn path ->
      assert path == "repos/acme/spek/contents/.credo.exs"
      {:ok, %{"content" => Base.encode64(contents)}}
    end
  end

  describe "run/2" do
    test "is ok when the file matches" do
      assert Credo.run(@spek, stub(Render.credo(@spek))) == :ok
    end

    test "is ok when only the final newline differs" do
      trimmed = @spek |> Render.credo() |> String.trim_trailing()

      assert Credo.run(@spek, stub(trimmed)) == :ok
    end

    test "reports a magnitude when the file differs" do
      changed =
        @spek
        |> Render.credo()
        |> String.replace("max_length: 80", "max_length: 120")

      assert {:differs, 2} = Credo.run(@spek, stub(changed))
    end

    test "is missing when the file does not exist" do
      fetcher = fn _ -> {:error, {:http, 404, "Not Found"}} end

      assert Credo.run(@spek, fetcher) == :missing
    end

    test "reports a failed request as an error, not as drift" do
      fetcher = fn _ -> {:error, {:http, 403, "Forbidden"}} end

      assert {:error, _} = Credo.run(@spek, fetcher)
    end
  end
end
