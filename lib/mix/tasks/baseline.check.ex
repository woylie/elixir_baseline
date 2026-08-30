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
  alias ElixirBaseline.Render

  @switches [repo: :keep, config: :string]

  @indent "  "

  @concurrency 4

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    specs = Config.repos(Options.repos(opts))
    if specs == [], do: Mix.raise("no configured repos matched")

    width = width(specs)

    results =
      specs
      |> Task.async_stream(&{&1, Check.run(&1)},
        ordered: true,
        max_concurrency: @concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {spec, findings} = result} ->
        report(spec, findings, width)
        result
      end)

    summarise(results)
  end

  defp report(spec, findings, width) do
    case Enum.reject(findings, &ok?/1) do
      [] -> :ok
      drifted -> Mix.shell().info(entry(Config.slug(spec), drifted, width))
    end
  end

  defp ok?({_path, finding}), do: finding == :ok

  defp width(specs) do
    specs
    |> Enum.flat_map(fn spec ->
      paths = spec |> Render.files() |> Map.keys()

      [Config.slug(spec) | Enum.map(paths, &(@indent <> &1))]
    end)
    |> Enum.map(&String.length/1)
    |> Enum.max()
  end

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

  defp summarise(results) do
    findings = Enum.flat_map(results, fn {_spec, findings} -> findings end)
    drifted = Enum.reject(findings, &ok?/1)
    matching = length(findings) - length(drifted)
    lead = if drifted == [], do: "", else: "\n"

    Mix.shell().info(
      "#{lead}#{matching}/#{length(findings)} files match the baseline."
    )

    if drifted != [] do
      Mix.raise("#{length(drifted)} file(s) drifted from the baseline")
    end
  end
end
