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
    doggo: [group: :library],
    ecto_nested_changeset: [group: :library],
    elixir_baseline: [group: :library],
    ex_icon: [group: :library],
    flop: [group: :library],
    flop_phoenix: [group: :library],
    let_me: [group: :library],
    spek: [group: :library]
  ]
]
