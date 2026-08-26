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

  @switches [repo: :keep, config: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    results =
      for spec <- Config.repos(config_opts(opts)) do
        {spec, Check.Credo.run(spec)}
      end

    if results == [], do: Mix.raise("no configured repos matched")

    report(results)
    summarise(results)
  end

  defp config_opts(opts) do
    only = Keyword.get_values(opts, :repo)

    [path: opts[:config], only: if(only == [], do: nil, else: only)]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp report(results) do
    width =
      results
      |> Enum.map(fn {spec, _} -> String.length(Config.slug(spec)) end)
      |> Enum.max()

    Enum.each(results, fn {spec, finding} ->
      slug = String.pad_trailing(Config.slug(spec), width + 2)
      Mix.shell().info(slug <> line(finding))
    end)
  end

  defp line(:ok), do: "ok"
  defp line(:missing), do: "missing"
  defp line({:differs, n}), do: "differs -- #{n} lines not in common"
  defp line({:error, reason}), do: "error -- #{reason}"

  defp summarise(results) do
    drifted = Enum.reject(results, fn {_spec, finding} -> finding == :ok end)
    matching = length(results) - length(drifted)

    Mix.shell().info(
      "\n#{matching}/#{length(results)} repos match the baseline."
    )

    if drifted != [] do
      Mix.raise("#{length(drifted)} repo(s) drifted from the baseline")
    end
  end
end
