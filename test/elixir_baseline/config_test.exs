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
        library: [],
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

    # all:, since the :library group sets nothing
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
  test "holds one project at its root if a repo names none",
       %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "acme"]], repos: [a: []]]

    assert [%{projects: [%{path: "."}]}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "holds no project at its root if a repo names none there",
       %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "acme"]],
      repos: [
        mono: [
          projects: [
            my_app: [path: "elixir/my_app"],
            tools: [path: "elixir/tools"]
          ]
        ]
      ]
    ]

    assert [%{projects: [my_app, tools]}] = repos(dir, manifest)
    assert my_app.path == "elixir/my_app"
    assert tools.path == "elixir/tools"
  end

  @tag :tmp_dir
  test "resolves a project over its repo, then over its own group",
       %{tmp_dir: dir} do
    manifest = [
      defaults: [
        all: [owner: "acme", line_length: 98],
        library: [],
        application: [line_length: 100]
      ],
      repos: [
        lib: [
          group: :library,
          line_length: 80,
          projects: [
            inherits: [],
            grouped: [group: :application],
            own: [line_length: 120]
          ]
        ]
      ]
    ]

    assert [%{projects: [inherits, grouped, own]}] = repos(dir, manifest)

    assert {"acme/lib", "inherits", 80, :library} == identity(inherits)
    assert {"acme/lib", "grouped", 80, :application} == identity(grouped)
    assert {"acme/lib", "own", 120, :library} == identity(own)
  end

  @tag :tmp_dir
  test "puts a project in a directory named after it", %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [r: [projects: [r: [path: "."], demo: []]]]
    ]

    assert [%{projects: [%{path: "."}, %{path: "demo"}]}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "normalizes a leading ./ and a trailing slash", %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [r: [projects: [x: [path: "./apps/x/"]]]]
    ]

    assert [%{projects: [%{path: "apps/x"}]}] = repos(dir, manifest)
  end

  @tag :tmp_dir
  test "rejects a path pointing outside the repo", %{tmp_dir: dir} do
    for path <- ~w(/etc ../sibling demo/../..) do
      manifest = [
        defaults: [all: [owner: "a"]],
        repos: [r: [projects: [d: [path: path]]]]
      ]

      assert_raise ArgumentError,
                   ~r/expected a path inside the repository/,
                   fn ->
                     repos(dir, manifest)
                   end
    end
  end

  @tag :tmp_dir
  test "rejects two projects at the same path", %{tmp_dir: dir} do
    manifest = [
      defaults: [all: [owner: "a"]],
      repos: [r: [projects: [demo: [], other: [path: "demo"]]]]
    ]

    assert_raise ArgumentError, ~r/Duplicate project path in repo r/, fn ->
      repos(dir, manifest)
    end
  end

  @tag :tmp_dir
  test "rejects the options a project cannot set", %{tmp_dir: dir} do
    for {option, value} <- [owner: "other", projects: []] do
      manifest = [
        defaults: [all: [owner: "a"]],
        repos: [r: [projects: [d: [{option, value}]]]]
      ]

      assert_raise ArgumentError, ~r/unknown options \[:#{option}\]/, fn ->
        repos(dir, manifest)
      end
    end
  end

  @tag :tmp_dir
  test "resolves templates and file selection at every level", %{tmp_dir: dir} do
    house = Path.join(dir, "house")
    special = Path.join(dir, "special")
    Enum.each([house, special], &File.mkdir_p!(Path.join(&1, "project")))

    manifest = [
      defaults: [all: [owner: "a"], library: [templates: [:default, house]]],
      repos: [
        r: [
          group: :library,
          exclude: ["repo/CODEOWNERS"],
          projects: [
            inherits: [],
            own: [
              templates: [special],
              include: ["project/.credo.exs"],
              exclude: ["project/.credo.exs"]
            ]
          ]
        ]
      ]
    ]

    assert [repo] = repos(dir, manifest)
    assert [inherits, own] = repo.projects

    assert repo.templates == [:default, house]
    assert inherits.templates == [:default, house]

    assert own.templates == [special]

    assert repo.exclude == ["repo/CODEOWNERS"]
    assert inherits.exclude == ["repo/CODEOWNERS"]
    assert own.exclude == ["project/.credo.exs"]

    refute Map.has_key?(repo, :include)
    refute Map.has_key?(inherits, :include)
    assert own.include == ["project/.credo.exs"]
  end

  @tag :tmp_dir
  test "rejects a template directory that is not one", %{tmp_dir: dir} do
    missing = Path.join(dir, "missing")
    scopeless = Path.join(dir, "scopeless")
    File.mkdir_p!(scopeless)

    for {path, message} <- [
          {missing, ~r/expected a directory/},
          {scopeless, ~r/expected a directory holding repo or project/}
        ] do
      manifest = [
        defaults: [all: [owner: "a"]],
        repos: [r: [templates: [path]]]
      ]

      assert_raise ArgumentError, message, fn -> repos(dir, manifest) end
    end
  end

  @tag :tmp_dir
  test "resolves each key of extra on its own", %{tmp_dir: dir} do
    manifest = [
      defaults: [
        all: [owner: "a", extra: [registry: "ghcr.io", tag: "latest"]],
        library: [extra: [tag: "stable"]]
      ],
      repos: [
        r: [
          group: :library,
          extra: [team: "core"],
          projects: [p: [path: ".", extra: [tag: "edge"]]]
        ]
      ]
    ]

    assert [%{extra: repo, projects: [%{extra: project}]}] =
             repos(dir, manifest)

    assert Enum.sort(repo) == [registry: "ghcr.io", tag: "stable", team: "core"]

    assert Enum.sort(project) == [
             registry: "ghcr.io",
             tag: "edge",
             team: "core"
           ]
  end

  @tag :tmp_dir
  test "folds several groups in the order they are written", %{tmp_dir: dir} do
    manifest = [
      defaults: [
        all: [owner: "acme", line_length: 80, extra: [ci: "basic"]],
        application: [line_length: 98, extra: [ci: "deploy", sobelow: true]],
        phoenix: [extra: [ci: "assets"]]
      ],
      repos: [
        api: [group: :application],
        web: [group: [:application, :phoenix]],
        legacy: [group: [:phoenix, :application]]
      ]
    ]

    assert [api, web, legacy] = repos(dir, manifest)

    assert {98, [ci: "deploy", sobelow: true]} == {api.line_length, api.extra}

    assert web.line_length == 98
    assert Enum.sort(web.extra) == [ci: "assets", sobelow: true]

    assert Enum.sort(legacy.extra) == [ci: "deploy", sobelow: true]
  end

  @tag :tmp_dir
  test "rejects a group that is not defined under defaults", %{tmp_dir: dir} do
    on_repo = [
      defaults: [all: [owner: "a"], library: []],
      repos: [r: [group: [:library, :libary]]]
    ]

    on_project = [
      defaults: [all: [owner: "a"], library: []],
      repos: [r: [projects: [p: [group: :libary]]]]
    ]

    for {context, manifest} <- [{"repo r", on_repo}, {"project p", on_project}] do
      assert_raise ArgumentError,
                   ~r/Unknown group for #{context}: libary.*known: \[:library\]/s,
                   fn -> repos(dir, manifest) end
    end
  end

  @tag :tmp_dir
  test "rejects all as a group of its own", %{tmp_dir: dir} do
    manifest = [defaults: [all: [owner: "a"]], repos: [r: [group: :all]]]

    assert_raise ArgumentError, ~r/Invalid group for repo r: all/, fn ->
      repos(dir, manifest)
    end
  end

  @tag :tmp_dir
  test "rejects a repo with no owner anywhere", %{tmp_dir: dir} do
    manifest = [defaults: [all: [line_length: 80]], repos: [r: []]]

    assert_raise ArgumentError, ~r/Missing owner for repo r/, fn ->
      repos(dir, manifest)
    end
  end

  @tag :tmp_dir
  test "rejects a name written twice", %{tmp_dir: dir} do
    written = [
      {"group: all", [defaults: [all: [owner: "a"], all: []], repos: []]},
      {"repo: r", [defaults: [all: [owner: "a"]], repos: [r: [], r: []]]},
      {"project: p",
       [
         defaults: [all: [owner: "a"]],
         repos: [r: [projects: [p: [path: "a"], p: [path: "b"]]]]
       ]}
    ]

    for {name, manifest} <- written do
      assert_raise ArgumentError, ~r/Duplicate #{name}/, fn ->
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

    project = [
      defaults: [all: [owner: "a"]],
      repos: [r: [projects: [d: [line_length: "eighty"]]]]
    ]

    for {context, manifest} <- [
          {"group all", group},
          {"repo r", repo},
          {"repo r", project}
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
