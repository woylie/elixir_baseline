defmodule Mix.Tasks.Baseline.Check do
  @shortdoc "Reports which generated files have drifted from the baseline"

  @moduledoc """
  Reports whether the files each enrolled repo generates match its templates.

  ## Command line options

    * `--repo` - check only this repo. May be given more than once.
    * `--config` - path to the config. Defaults to `.baseline.exs`.
  """

  use Mix.Task

  alias ElixirBaseline.Check
  alias ElixirBaseline.Config
  alias ElixirBaseline.Diff
  alias ElixirBaseline.Options

  @switches [repo: :keep, config: :string]

  @indent "  "

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    results =
      for spec <- Config.repos(Options.repos(opts)) do
        {spec, Check.run(spec)}
      end

    if results == [], do: Mix.raise("no configured repos matched")

    summarise(results, report(results))
  end

  defp report(results) do
    drifted =
      results
      |> Enum.map(fn {spec, findings} ->
        {spec, Enum.reject(findings, &ok?/1)}
      end)
      |> Enum.reject(fn {_spec, findings} -> findings == [] end)

    width = width(drifted)

    Enum.each(drifted, fn {spec, findings} ->
      Mix.shell().info(entry(Config.slug(spec), findings, width))
    end)

    drifted != []
  end

  defp ok?({_path, finding}), do: finding == :ok

  defp width([]), do: 0

  defp width(drifted) do
    drifted
    |> Enum.flat_map(fn {spec, findings} ->
      [
        Config.slug(spec)
        | Enum.map(findings, fn {path, _} -> @indent <> path end)
      ]
    end)
    |> Enum.map(&String.length/1)
    |> Enum.max()
  end

  # Only what drifted is worth a line, and the file it drifted in is named
  # under the repo, so that a subproject is as visible as the repo it sits in.
  defp entry(slug, findings, width) do
    Enum.reduce(findings, slug, fn {path, finding}, acc ->
      acc <> "\n" <> pad(@indent <> path, width) <> describe(finding)
    end)
  end

  defp pad(label, width), do: String.pad_trailing(label, width + 2)

  defp describe(:ok), do: "ok"
  defp describe({:missing, _expected}), do: "missing"
  defp describe({:error, reason}), do: "error -- #{reason}"

  defp describe({:differs, diff}) do
    {added, removed} = Diff.counts(diff)

    "differs -- +#{added} -#{removed}"
  end

  defp summarise(results, reported?) do
    findings = Enum.flat_map(results, fn {_spec, findings} -> findings end)
    drifted = Enum.reject(findings, &ok?/1)
    matching = length(findings) - length(drifted)
    lead = if reported?, do: "\n", else: ""

    Mix.shell().info(
      "#{lead}#{matching}/#{length(findings)} files match the baseline."
    )

    if drifted != [] do
      Mix.raise("#{length(drifted)} file(s) drifted from the baseline")
    end
  end
end
