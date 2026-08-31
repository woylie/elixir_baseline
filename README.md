# Elixir Baseline

Tool for sharing tooling configuration between Elixir repos. Detects drift from
a baseline configuration and opens pull requests to fix it, and reports the
GitHub settings a pull request cannot fix.

## Features

### Generated files

Owned by the tool and rendered from a template. When the template is changed,
the file in the repository is overwritten as a whole.

The default templates include:

- `.credo.exs`
- `renovate.json`
- `.github/CODEOWNERS`
- `.github/workflows/hadolint.yaml`
- `.github/workflows/zizmor.yaml`

Pinned hashes in Github Actions workflows are not overwritten from templates.

### Patched files

Owned in parts and patched when settings are changed.

Currently supported:

- `line_length` in `.formatter.exs` (also applied in the default `.credo.exs`
  template)

### Github settings

GitHub settings are read through the API and only reported.

Currently supported checks:

- `SECURITY.md` exists in either the repo or inherited from the owner's
  `.github` repo. Only applied to public repositories.
- private vulnerability reporting is enabled

## Requirements

You need the [`gh` CLI](https://cli.github.com) installed and authenticated.

## Installation

To use this tool, you need to clone it and create a configuration file.

```bash
git clone https://github.com/woylie/elixir_baseline.git
cd elixir_baseline
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
    spek: [group: :library]
  ]
]
```

The lookup order of the repo settings is:

- configuration under `repos`
- group configuration under `defaults`
- "all" group configuration
- elixir_baseline's own defaults

## Usage

```
mix baseline.check              # report which files and settings have drifted
mix baseline.check --repo spek
mix baseline.pr                 # open a pull request per drifted repo
mix baseline.pr --repo spek
mix baseline.pr --dry-run       # what would change, writing nothing
mix baseline.pr --dry-run --diff
mix baseline.pr --interactive   # confirm each file before it is written
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
woylie/ecto_nested_changeset
  .github/workflows/zizmor.yaml    missing
woylie/flop
  .github/workflows/zizmor.yaml    missing
woylie/let_me
  .github/workflows/zizmor.yaml    missing
woylie/spek
  private vulnerability reporting  disabled
    run: gh api --method PUT repos/woylie/spek/private-vulnerability-reporting
woylie/coach
  .github/workflows/hadolint.yaml  missing
woylie/tuduli
  .github/workflows/hadolint.yaml  missing

51/56 files match the baseline.
17/18 settings match the baseline. 2 skipped.

Run mix baseline.pr to update the files.
** (Mix) 5 file(s) and 1 setting(s) drifted from the baseline
```

```
$ mix baseline.pr
doggo: unchanged
ecto_nested_changeset: cloning... pushing... https://github.com/woylie/ecto_nested_changeset/pull/457
elixir_baseline: unchanged
ex_icon: unchanged
flop: cloning... pushing... https://github.com/woylie/flop/pull/717
flop_phoenix: unchanged
let_me: cloning... pushing... https://github.com/woylie/let_me/pull/213
spek: unchanged
coach: cloning... pushing... https://github.com/woylie/coach/pull/89
tuduli: cloning... pushing... https://github.com/woylie/tuduli/pull/42
```

## Templates

The templates are in the `priv/templates` folder, split into `repo` and
`project`. To use your own templates instead, list the directories under
`templates`. `:default` in that list stands for the templates that ship with
this tool.
