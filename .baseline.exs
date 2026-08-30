[
  defaults: [
    # The `all` group contains defaults that are applied to all repos.
    # You can add any number of additional groups under `defaults`. They are
    # referenced with the `group` option under `repos`.
    all: [
      owner: "woylie",
      line_length: 80
    ],
    library: [
      exclude: ["repo/.github/workflows/hadolint.yaml"],
      extra: [renovate_presets: ["github>woylie/renovate-presets:library"]]
    ],
    application: [
      extra: [renovate_presets: ["github>woylie/renovate-presets:application"]]
    ]
  ],
  repos: [
    doggo: [
      group: :library,
      projects: [doggo: [path: "."], demo: [group: :application]]
    ],
    ecto_nested_changeset: [
      group: :library,
      projects: [
        ecto_nested_changeset: [path: "."],
        example: [group: :application]
      ]
    ],
    elixir_baseline: [group: :library],
    ex_icon: [group: :library],
    flop: [group: :library],
    flop_phoenix: [group: :library],
    let_me: [group: :library],
    spek: [group: :library]
  ]
]
