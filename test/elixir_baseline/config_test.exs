defmodule ElixirBaseline.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Config

  defp repos(dir, manifest, opts \\ []) do
    path = Path.join(dir, ".baseline.exs")
    File.write!(path, inspect(manifest, limit: :infinity))
    Config.repos(Keyword.put(opts, :path, path))
  end

  defp identity(spec) do
    {Config.slug(spec), spec.path, spec.line_length, spec.group}
  end

  @tag :tmp_dir
  test "resolves each level over the one before", %{tmp_dir: dir} do
    manifest = [
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
    manifest = [defaults: [all: [owner: "acme"]], repos: [a: []]]

    assert [%{line_length: 80}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "resolves no subprojects where a repo declares none", %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "acme"]], repos: [a: []]]

    assert [%{subprojects: []}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "resolves a subproject over its parent, then over its own group",
       %{tmp_dir: dir} do
    manifest = [
      defaults: [
        all: [owner: "acme", line_length: 98],
        application: [line_length: 100]
      ],
      repos: [
        lib: [
          group: :library,
          line_length: 80,
          subprojects: [
            inherits: [],
            grouped: [group: :application],
            own: [line_length: 120]
          ]
        ]
      ]
    ]

    assert [%{subprojects: [inherits, grouped, own]}] = repos(dir, manifest)

    assert {"acme/lib", "inherits", 80, :library} == identity(inherits)
    assert {"acme/lib", "grouped", 80, :application} == identity(grouped)
    assert {"acme/lib", "own", 120, :library} == identity(own)
  end

  @tag :tmp_dir
  test "puts a repo at the root and a subproject in a directory named after it",
       %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [r: [subprojects: [demo: []]]]
    ]

    assert [%{path: ".", subprojects: [%{path: "demo"}]}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "puts a project where its path says", %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [
        mono: [
          path: "elixir/my_app",
          subprojects: [demo: [path: "elixir/my_app/demo"]]
        ]
      ]
    ]

    assert [%{path: "elixir/my_app", subprojects: [demo]}] =
             repos(dir, manifest)

    assert demo.path == "elixir/my_app/demo"
  end

  @tag :tmp_dir
  test "normalizes a leading ./ and a trailing slash", %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "a"]], repos: [r: [path: "./apps/x/"]]]

    assert [%{path: "apps/x"}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "rejects a path pointing outside the repo", %{tmp_dir: dir} do
    for path <- ~w(/etc ../sibling demo/../..) do
      subproject = [
        defaults: [all: [owner: "a"]],
        repos: [r: [subprojects: [d: [path: path]]]]
      ]

      repo = [defaults: [all: [owner: "a"]], repos: [r: [path: path]]]

      for manifest <- [subproject, repo] do
        assert_raise ArgumentError,
                     ~r/expected a path inside the repository/,
                     fn ->
                       repos(dir, manifest)
                     end
      end
    end
  end

  @tag :tmp_dir
  test "rejects two projects at the same path", %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [r: [subprojects: [demo: [], other: [path: "demo"]]]]
    ]

    assert_raise ArgumentError, ~r/Duplicate project path in repo r/, fn ->
      repos(dir, manifest)
    end
  end

  @tag :tmp_dir
  test "rejects the options a subproject cannot set", %{tmp_dir: dir} do
    for {option, value} <- [owner: "other", subprojects: []] do
      manifest = [
        defaults: [all: [owner: "a"]],
        repos: [r: [subprojects: [d: [{option, value}]]]]
      ]

      assert_raise ArgumentError, ~r/unknown options \[:#{option}\]/, fn ->
        repos(dir, manifest)
      end
    end
  end

  @tag :tmp_dir
  test "rejects an unknown option", %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "a"]], repos: [r: [line_lenght: 80]]]

    assert_raise ArgumentError, ~r/unknown options \[:line_lenght\]/, fn ->
      repos(dir, manifest)
    end
  end

  @tag :tmp_dir
  test "rejects a wrong-typed value", %{tmp_dir: dir} do
    group = [defaults: [all: [line_length: "eighty"]], repos: []]
    repo = [defaults: [all: [owner: "a"]], repos: [r: [line_length: "eighty"]]]

    subproject = [
      defaults: [all: [owner: "a"]],
      repos: [r: [subprojects: [d: [line_length: "eighty"]]]]
    ]

    # the error names the group or the repo the value was set on
    for {context, manifest} <- [
          {"group all", group},
          {"repo r", repo},
          {"repo r", subproject}
        ] do
      assert_raise ArgumentError,
                   ~r/Invalid configuration for #{context}.*:line_length/s,
                   fn -> repos(dir, manifest) end
    end
  end

  @tag :tmp_dir
  test "filters by name, keeping manifest order", %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "a"]], repos: [z: [], b: [], m: []]]

    filtered = repos(dir, manifest, only: ["m", "z"])

    assert Enum.map(repos(dir, manifest), & &1.name) == [:z, :b, :m]
    assert Enum.map(filtered, & &1.name) == [:z, :m]
  end
end
