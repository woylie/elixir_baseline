defmodule Mix.Tasks.Baseline.Check do
  @shortdoc "Reports which repos' Credo config has drifted from the baseline"

  @moduledoc """
  Reports whether each enrolled repo's `.credo.exs` matches the shared template.

  ## Command line options

    * `--repo` - check only this repo. May be given more than once.
    * `--config` - path to the config. Defaults to `.baseline.exs`.
  """

  use Mix.Task

  alias ElixirBaseline.Check
  alias ElixirBaseline.Config
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

    report(results)
    summarise(results)
  end

  defp report(results) do
    width =
      results
      |> Enum.flat_map(fn {spec, findings} ->
        [
          Config.slug(spec)
          | Enum.map(findings, fn {path, _} -> @indent <> path end)
        ]
      end)
      |> Enum.map(&String.length/1)
      |> Enum.max()

    Enum.each(results, fn {spec, findings} ->
      Mix.shell().info(entry(Config.slug(spec), findings, width))
    end)
  end

  defp entry(slug, [], width), do: pad(slug, width) <> "no projects"

  defp entry(slug, [{path, finding}] = findings, width) do
    if Path.dirname(path) == "." do
      pad(slug, width) <> describe(finding)
    else
      expanded(slug, findings, width)
    end
  end

  defp entry(slug, findings, width), do: expanded(slug, findings, width)

  defp expanded(slug, findings, width) do
    Enum.reduce(findings, slug, fn {path, finding}, acc ->
      acc <> "\n" <> pad(@indent <> path, width) <> describe(finding)
    end)
  end

  defp pad(label, width), do: String.pad_trailing(label, width + 2)

  defp describe(:ok), do: "ok"
  defp describe(:missing), do: "missing"
  defp describe({:differs, n}), do: "differs -- #{n} lines not in common"
  defp describe({:error, reason}), do: "error -- #{reason}"

  defp summarise(results) do
    findings = Enum.flat_map(results, fn {_spec, findings} -> findings end)
    drifted = Enum.reject(findings, fn {_path, finding} -> finding == :ok end)
    matching = length(findings) - length(drifted)

    Mix.shell().info(
      "\n#{matching}/#{length(findings)} files match the baseline."
    )

    if drifted != [] do
      Mix.raise("#{length(drifted)} file(s) drifted from the baseline")
    end
  end
end
