defmodule Mix.Tasks.Baseline.Check do
  @shortdoc "Reports which generated files and GitHub settings have drifted"

  @moduledoc """
  Reports whether the files each enrolled repo generates match its templates,
  whether its GitHub settings match the baseline, and whether it holds a
  project the config does not enroll.

  A drifted file is fixed by `mix baseline.pr`. A drifted setting is changed in
  GitHub and an unclaimed file in the config, so the three are counted apart.

  ## Command line options

    * `--repo` - check only this repo. May be given more than once.
    * `--config` - path to the config. Defaults to `.baseline.exs`.
  """

  use Mix.Task

  alias ElixirBaseline.Check
  alias ElixirBaseline.Check.Settings
  alias ElixirBaseline.Check.Unclaimed
  alias ElixirBaseline.Config
  alias ElixirBaseline.Diff
  alias ElixirBaseline.Options
  alias ElixirBaseline.Render
  alias ElixirBaseline.Repository

  @switches [repo: :keep, config: :string]

  @indent "  "

  @concurrency 4

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    specs = Config.repos(Options.repos(opts))
    if specs == [], do: Mix.raise("no configured repos matched")

    # What GitHub says decides which files a repo generates, so the width below
    # needs it too.
    specs = Repository.resolve_all(specs)
    width = width(specs)

    results =
      specs
      |> Task.async_stream(
        &{&1, Check.run(&1), Settings.run(&1), Unclaimed.run(&1)},
        ordered: true,
        max_concurrency: @concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {spec, files, settings, unclaimed} = result} ->
        report(spec, files ++ settings ++ unclaimed, width)
        result
      end)

    summarise(results)
  end

  defp report(spec, findings, width) do
    case Enum.reject(findings, &quiet?/1) do
      [] -> :ok
      drifted -> Mix.shell().info(entry(Config.slug(spec), drifted, width))
    end
  end

  defp ok?({_label, finding}), do: finding == :ok

  defp quiet?({_label, finding}) do
    finding == :ok or match?({:skipped, _reason}, finding)
  end

  defp skipped?({_label, finding}), do: match?({:skipped, _reason}, finding)

  defp width(specs) do
    specs
    |> Enum.flat_map(fn spec ->
      generated = spec |> Render.files() |> Map.keys()
      seeded = spec |> Render.seeds() |> Map.keys()
      unclaimed = for {path, _finding} <- Unclaimed.run(spec), do: path
      labels = generated ++ seeded ++ unclaimed ++ Settings.labels()

      [Config.slug(spec) | Enum.map(labels, &(@indent <> &1))]
    end)
    |> Enum.map(&String.length/1)
    |> Enum.max()
  end

  defp entry(slug, findings, width) do
    Enum.reduce(findings, slug, fn {label, finding}, acc ->
      acc <>
        "\n" <>
        pad(@indent <> label, width) <> describe(finding) <> remedy(finding)
    end)
  end

  defp remedy({:drift, _state, remedy}), do: "\n#{@indent}#{@indent}#{remedy}"
  defp remedy(_finding), do: ""

  defp pad(label, width), do: String.pad_trailing(label, width + 2)

  defp describe(:ok), do: "ok"
  defp describe({:missing, _expected}), do: "missing"
  defp describe({:unpatchable, reason}), do: "needs a hand -- #{reason}"
  defp describe({:error, reason}), do: "error -- #{reason}"

  defp describe({:differs, diff}) do
    {added, removed} = Diff.counts(diff)

    "differs -- +#{added} -#{removed}"
  end

  defp describe({:drift, state, _remedy}), do: state

  defp summarise(results) do
    files = collect(results, 1)
    settings = collect(results, 2)
    unclaimed = collect(results, 3)
    lead = if drifted(files ++ settings ++ unclaimed) == 0, do: "", else: "\n"

    Mix.shell().info(
      lead <>
        tally("files", files) <>
        "\n" <>
        tally("settings", settings) <> orphans(unclaimed) <> hint(files)
    )

    raise_drift(files, settings, unclaimed)
  end

  defp collect(results, index) do
    Enum.flat_map(results, &elem(&1, index))
  end

  # No denominator: an unclaimed file is a finding rather than one of a known
  # set, so a count of nothing says nothing.
  defp orphans([]), do: ""
  defp orphans(unclaimed), do: "\n#{length(unclaimed)} unclaimed file(s)."

  defp drifted(findings), do: Enum.count(findings, &(not quiet?(&1)))

  defp hint(files) do
    if drifted(files) == 0 do
      ""
    else
      "\n\nRun mix baseline.pr to update the files."
    end
  end

  defp raise_drift(files, settings, unclaimed) do
    parts =
      [
        {"file", drifted(files)},
        {"setting", drifted(settings)},
        {"unclaimed file", drifted(unclaimed)}
      ]
      |> Enum.reject(fn {_kind, count} -> count == 0 end)
      |> Enum.map(fn {kind, count} -> "#{count} #{kind}(s)" end)

    if parts != [] do
      Mix.raise("#{Enum.join(parts, " and ")} drifted from the baseline")
    end
  end

  defp tally(kind, findings) do
    {skipped, applicable} = Enum.split_with(findings, &skipped?/1)
    matching = Enum.count(applicable, &ok?/1)
    aside = if skipped == [], do: "", else: " #{length(skipped)} skipped."

    "#{matching}/#{length(applicable)} #{kind} match the baseline.#{aside}"
  end
end
