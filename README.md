# Elixir Baseline

Tool for sharing tooling configuration between Elixir repos. Detects drift from
a baseline configuration and opens pull requests to fix it, and reports the
GitHub settings and the unenrolled projects a pull request cannot fix.

## Features

### Generated files

Owned by the tool and rendered from a template. When the template is changed,
the file in the repository is overwritten as a whole.

The default templates include:

- `.credo.exs`
- `renovate.json`
- `SECURITY.md` (only generated for public repositories)
- `.github/CODEOWNERS`
- `.github/workflows/hadolint.yaml` (only generated for repositories with a
  `Dockerfile`)
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
  `.github` repo (only public repositories).
- Private vulnerability reporting is enabled (only public repositories).

### Unclaimed files

The drift check only looks at the paths the configuration expects, so a Mix
project that is not listed under `projects` is invisible to it and its
repository reads as fully covered.

The unclaimed check searches the other way. It goes over every path in the
repository and reports a `mix.exs`, or a file one of the project templates
generates, sitting in a directory that no configured project claims. That
catches a project dropped from the configuration by mistake, and a nested
application that was added to a repository but never enrolled.

An unclaimed file is fixed in the configuration rather than by a pull request,
so it is counted separately.

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
    all: [
      owner: "woylie",
      line_length: 80,
      conditions: %{
        "repo/.github/workflows/hadolint.yaml" => {:exists, "Dockerfile"}
      },
      extra: [
        security_contacts: ["[Contact form](https://example.com/contact)"]
      ]
    ],
    library: [
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
  SECURITY.md                      missing
woylie/elixir_baseline
  SECURITY.md                      missing
woylie/ex_icon
  SECURITY.md                      missing
woylie/flop
  .github/workflows/zizmor.yaml    missing
  SECURITY.md                      missing
woylie/let_me
  .github/workflows/zizmor.yaml    missing
  SECURITY.md                      missing
woylie/spek
  SECURITY.md                      missing
  private vulnerability reporting  disabled
    run: gh api --method PUT repos/woylie/spek/private-vulnerability-reporting

43/52 files match the baseline.
15/16 settings match the baseline.

Run mix baseline.pr to update the files.
** (Mix) 9 file(s) and 1 setting(s) drifted from the baseline
```

```
$ mix baseline.pr
doggo: unchanged
ecto_nested_changeset: cloning... pushing... https://github.com/woylie/ecto_nested_changeset/pull/457
elixir_baseline: cloning... pushing... https://github.com/woylie/elixir_baseline/pull/12
ex_icon: cloning... pushing... https://github.com/woylie/ex_icon/pull/28
flop: cloning... pushing... https://github.com/woylie/flop/pull/717
flop_phoenix: unchanged
let_me: cloning... pushing... https://github.com/woylie/let_me/pull/213
spek: cloning... pushing... https://github.com/woylie/spek/pull/71
```

## Templates

The templates are in the `priv/templates` folder, split into `repo` and
`project`. To use your own templates instead, list the directories under
`templates`. `:default` in that list stands for the templates that ship with
this tool.

A template is referenced by its full relative path in the template folder,
without the `.eex`. `include` and `exclude` options are supported. You can also
set `conditions` that must be met for a template to be generated:

```elixir
conditions: %{
  "repo/.github/workflows/hadolint.yaml" => {:exists, "Dockerfile"}
}
```

The path in a condition is relative to the repository root.
