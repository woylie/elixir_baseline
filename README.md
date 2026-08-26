# Elixir Baseline

Tool for sharing tooling configuration between Elixir repos. Detects drift from
a baseline configuration and opens pull requests to fix it.

## Covered Tooling

- Credo configuration

## Requirements

You need the [`gh` CLI](https://cli.github.com) installed and authenticated.

## Installation

To use this tool, you need to clone it and create a configuration file.

```bash
git clone https://github.com/woylie/elixir-baseline.git
cd elixir-baseline
cp .baseline.exs .baseline.override.exs
```

`.baseline.exs` is the default configuration I use for my own repositories. With
the commands above, it is copied to `.baseline.override.exs`, which you can
edit for your own repositories.

If `.baseline.override.exs` exists, the Mix tasks will use it as a default.
Otherwise, they fall back to `.baseline.exs`. You can also pass a different path
with the `--config` argument. Configuration files named `.baseline.*.exs` are
gitignored in this repository.

## Configuration

`.baseline.exs` lists all the repo settings:

```elixir
[
  defaults: [
    # The `all` group contains defaults that are applied to all repos.
    # You can add any number of additional groups under `defaults`. They are
    # referenced with the `group` option under `repos`.
    all: [owner: "woylie", line_length: 80],
    library: [],
    application: []
  ],
  repos: [
    doggo: [group: :library],
    spek: [group: :library]
  ]
]
```

The lookup order of the repo settings is:

- configuration under `repos`
- group configuration under `defaults`
- "all" group configuration
- elixir-baseline's own defaults

## Usage

```
mix baseline.check              # report which repos have drifted
mix baseline.check --repo spek
mix baseline.pr                 # open a pull request per drifted repo
mix baseline.pr --repo spek
```

Both tasks take `--repo`, which may be given more than once, and `--config` for
a config file elsewhere.

`check` reads each repo's default branch through the API without cloning the
repositories.

`pr` runs the check first and only clones the repos that need it. Each one is
cloned shallowly into a temporary directory. Re-running is safe.

## Example Outputs

```
$ mix baseline.check
woylie/doggo                  differs -- 163 lines not in common
woylie/ecto_nested_changeset  differs -- 167 lines not in common
woylie/ex_icon                differs -- 162 lines not in common
woylie/flop                   differs -- 167 lines not in common
woylie/flop_phoenix           differs -- 167 lines not in common
woylie/let_me                 ok
woylie/spek                   ok

2/7 repos match the baseline.
** (Mix) 5 repo(s) drifted from the baseline
```

```
$ mix baseline.pr
doggo: cloning... up to date https://github.com/woylie/doggo/pull/718
ecto_nested_changeset: cloning... up to date https://github.com/woylie/ecto_nested_changeset/pull/457
ex_icon: cloning... up to date https://github.com/woylie/ex_icon/pull/43
flop: cloning... up to date https://github.com/woylie/flop/pull/717
flop_phoenix: cloning... pushing... https://github.com/woylie/flop_phoenix/pull/469
let_me: unchanged
spek: unchanged
```

## Templates

You can check the templates in the `priv/templates` folder. To customize them,
you can edit them locally. In the future, you will be able to add the tool as a
dependency and add override templates in your own `priv` folder instead.
