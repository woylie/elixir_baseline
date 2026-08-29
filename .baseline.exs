[
  defaults: [
    # The `all` group contains defaults that are applied to all repos.
    # You can add any number of additional groups under `defaults`. They are
    # referenced with the `group` option under `repos`.
    all: [
      owner: "woylie",
      line_length: 80
    ],
    library: [],
    application: []
  ],
  repos: [
    doggo: [
      projects: [
        doggo: [path: ".", group: :library],
        demo: [group: :application]
      ]
    ],
    ecto_nested_changeset: [
      projects: [
        ecto_nested_changeset: [path: ".", group: :library],
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
