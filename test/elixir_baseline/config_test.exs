defmodule ElixirBaseline.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Config

  defp repos(dir, contents, opts \\ []) do
    path = Path.join(dir, ".baseline.exs")
    File.write!(path, contents)
    Config.repos(Keyword.put(opts, :path, path))
  end

  @tag :tmp_dir
  test "resolves each level over the one before", %{tmp_dir: dir} do
    manifest = """
    [
      defaults: [
        all: [owner: "acme", line_length: 98],
        application: [owner: "someorg"]
      ],
      repos: [
        lib: [group: :library],
        app: [group: :application],
        own: [group: :application, owner: "third", line_length: 120],
        plain: []
      ]
    ]
    """

    assert [lib, app, own, plain] = repos(dir, manifest)

    # all:, since there is no :library group
    assert {"acme/lib", 98} == {Config.slug(lib), lib.line_length}

    # :application wins for owner; line_length still comes from all:
    assert {"someorg/app", 98} == {Config.slug(app), app.line_length}

    # the repo's own spec wins for both
    assert {"third/own", 120} == {Config.slug(own), own.line_length}

    # no group, so all: and nothing else
    assert {"acme/plain", 98} == {Config.slug(plain), plain.line_length}
  end

  @tag :tmp_dir
  test "falls back to elixir_baseline's own defaults", %{tmp_dir: dir} do
    manifest = ~s|[defaults: [all: [owner: "acme"]], repos: [a: []]]|

    assert [%{line_length: 80}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "filters by name, keeping manifest order", %{tmp_dir: dir} do
    manifest = ~s|[defaults: [all: [owner: "a"]], repos: [z: [], b: [], m: []]]|

    filtered = repos(dir, manifest, only: ["m", "z"])

    assert Enum.map(repos(dir, manifest), & &1.name) == [:z, :b, :m]
    assert Enum.map(filtered, & &1.name) == [:z, :m]
  end
end
