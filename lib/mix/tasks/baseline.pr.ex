defmodule Mix.Tasks.Baseline.Pr do
  @shortdoc "Opens a pull request per repo whose generated files have drifted"

  @moduledoc """
  Opens one pull request per configured repo whose generated files differ. One
  pull request updates every drifted file in that repo, on one branch, so that
  a re-run updates it rather than opening a second one.

  Each repo is cloned shallowly into a temporary directory, so no local checkout
  is needed and nothing you are working on is touched. Repos that already match
  are not cloned at all.

  Drift is measured against the default branch. If there is an open pull request
  with the proposed changes already, the task proposes the changes again until
  the PR is merged. Declining a file under `--interactive` does not affect open
  PRs.

  ## Command line options

    * `--repo` - update only this repo. May be given more than once.
    * `--config` - path to the config. Defaults to `.baseline.exs`.
    * `--dry-run` - report what would change and write nothing. Needs no clone,
      so it costs one request per generated file.
    * `--interactive` - confirm each suggested update before it is written.
    * `--diff` - with `--dry-run` or `--interactive`, print the changed lines
      rather than a count.
  """

  use Mix.Task

  alias ElixirBaseline.Check
  alias ElixirBaseline.Config
  alias ElixirBaseline.Diff
  alias ElixirBaseline.Options
  alias ElixirBaseline.Render

  @switches [
    repo: :keep,
    config: :string,
    dry_run: :boolean,
    diff: :boolean,
    interactive: :boolean
  ]

  @branch "baseline/update"
  @subject "update generated files from elixir_baseline"

  @indent "  "

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    validate!(opts)

    specs = Config.repos(Options.repos(opts))
    if specs == [], do: Mix.raise("no configured repos matched")

    if opts[:dry_run], do: dry_run(specs, opts), else: propose_all(specs, opts)
  end

  defp validate!(opts) do
    if opts[:dry_run] && opts[:interactive] do
      Mix.raise("--dry-run writes nothing, so there is nothing to confirm")
    end

    if opts[:interactive] && not terminal?() do
      Mix.raise("--interactive needs a terminal")
    end
  end

  defp terminal? do
    Keyword.get(:io.getopts(:standard_io), :stdin) == true
  end

  defp propose_all(specs, opts) do
    results =
      for spec <- specs do
        IO.write("#{spec.name}: ")
        outcome = propose(spec, opts)
        Mix.shell().info(line(outcome))
        {spec.name, outcome}
      end

    report_declined(results)

    failed = for {name, {:error, _reason}} <- results, do: name
    if failed != [], do: Mix.raise("could not read #{Enum.join(failed, ", ")}")
  end

  defp report_declined(results) do
    declined = Enum.sum(for {_name, outcome} <- results, do: declined(outcome))

    if declined > 0 do
      Mix.shell().info("\n#{declined} file(s) declined and left as they are.")
    end
  end

  defp declined({:declined, count}), do: count
  defp declined({:partial, _outcome, count}), do: count
  defp declined(_outcome), do: 0

  defp dry_run(specs, opts) do
    changed =
      for spec <- specs,
          {path, finding} <- Check.run(spec),
          finding != :ok,
          do: {spec, path, finding}

    Enum.each(changed, &report(&1, opts[:diff]))

    Mix.shell().info(
      "\n#{length(changed)} file(s) would change. Nothing written."
    )
  end

  defp report({spec, path, finding}, diff?) do
    Mix.shell().info("\n#{Config.slug(spec)}  #{path}  #{summary(finding)}")

    if diff?, do: Mix.shell().info(detail(finding))
  end

  defp summary({:missing, expected}) do
    {added, _removed} = expected |> creation() |> Diff.counts()

    "would be created, #{added} lines"
  end

  defp summary({:differs, diff}) do
    {added, removed} = Diff.counts(diff)

    "would change, +#{added} -#{removed}"
  end

  defp summary({:error, reason}), do: "error -- #{reason}"

  defp creation(expected), do: Diff.lines("", expected)

  defp detail({:missing, expected}), do: expected |> creation() |> Diff.format()
  defp detail({:differs, diff}), do: Diff.format(diff)
  defp detail({:error, _reason}), do: ""

  defp line(:unchanged), do: "unchanged"
  defp line({:up_to_date, nil}), do: "up to date"
  defp line({:up_to_date, url}), do: "up to date #{url}"
  defp line({:pull_request, url}), do: url
  defp line({:error, reason}), do: "error -- #{reason}"
  defp line({:declined, count}), do: "#{count} file(s) declined, nothing done"

  defp line({:partial, outcome, count}) do
    "#{line(outcome)} -- #{count} file(s) declined"
  end

  defp propose(spec, opts) do
    findings = Check.run(spec)
    errors = for {_path, {:error, reason}} <- findings, do: reason

    cond do
      errors != [] -> {:error, hd(errors)}
      Check.ok?(findings) -> :unchanged
      opts[:interactive] -> confirm(spec, findings, opts[:diff])
      true -> update(spec, [])
    end
  end

  defp confirm(spec, findings, diff?) do
    Mix.shell().info("")

    {accepted, declined} =
      findings
      |> Enum.reject(fn {_path, finding} -> finding == :ok end)
      |> Enum.split_with(fn {path, finding} -> ask(path, finding, diff?) end)

    IO.write(@indent)
    outcome(spec, accepted, declined)
  end

  defp ask(path, finding, diff?) do
    Mix.shell().info("#{@indent}#{path}  #{summary(finding)}")
    if diff?, do: Mix.shell().info(detail(finding))

    Mix.shell().yes?("#{@indent}Update #{path}?")
  end

  defp outcome(_spec, [], declined), do: {:declined, length(declined)}
  defp outcome(spec, _accepted, []), do: update(spec, [])

  defp outcome(spec, _accepted, declined) do
    paths = for {path, _finding} <- declined, do: path

    {:partial, update(spec, paths), length(declined)}
  end

  defp update(spec, declined) do
    dir = Path.join(System.tmp_dir!(), "baseline-#{spec.name}-#{unique()}")
    files = spec |> Render.files() |> Map.drop(declined)

    try do
      IO.write("cloning... ")
      clone!(spec, dir)
      start_branch(dir)
      write!(dir, files)
      publish(dir, Map.keys(files))
    after
      File.rm_rf!(dir)
    end
  end

  defp write!(dir, files) do
    Enum.each(files, fn {path, contents} ->
      target = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)
    end)
  end

  defp start_branch(dir) do
    refspec = "+refs/heads/#{@branch}:refs/remotes/origin/#{@branch}"

    if git(dir, ["fetch", "--quiet", "--depth", "1", "origin", refspec]) do
      git!(dir, ["switch", "--quiet", "-c", @branch, "origin/#{@branch}"])
    else
      git!(dir, ["switch", "--quiet", "-c", @branch])
    end
  end

  defp publish(dir, paths) do
    git!(dir, ["add" | paths])

    case changed(dir) do
      [] ->
        {:up_to_date, open_pull_request(dir)}

      changed ->
        git!(dir, ["commit", "--quiet", "-m", message(changed)])
        IO.write("pushing... ")
        git!(dir, ["push", "--quiet", "origin", @branch])
        {:pull_request, pull_request(dir)}
    end
  end

  defp changed(dir) do
    dir
    |> git!(["status", "--porcelain"])
    |> String.split("\n", trim: true)
    |> Enum.map(&(&1 |> String.slice(3..-1//1) |> String.trim()))
  end

  # The subject cannot name the files, since a repo may generate any number of
  # them, so the body does.
  defp message(changed) do
    Enum.join([@subject, "" | Enum.map(changed, &("- " <> &1))], "\n")
  end

  defp open_pull_request(dir) do
    args = ["pr", "list", "--head", @branch, "--json", "url"]

    with {out, 0} <- System.cmd("gh", args, cd: dir, stderr_to_stdout: true),
         {:ok, [%{"url" => url} | _]} <- JSON.decode(out) do
      url
    else
      _ -> nil
    end
  end

  defp pull_request(dir) do
    args = ["pr", "create", "--fill-first", "--head", @branch]

    case System.cmd("gh", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, _} -> existing!(out)
    end
  end

  defp existing!(out) do
    case Regex.run(~r{https://\S+}, out) do
      [url] -> url
      _ -> Mix.raise("gh pr create failed:\n#{out}")
    end
  end

  defp clone!(spec, dir) do
    slug = Config.slug(spec)
    args = ["repo", "clone", slug, dir, "--", "--depth", "1", "--quiet"]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, _} -> Mix.raise("gh repo clone #{slug} failed:\n#{out}")
    end
  end

  defp git!(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} ->
        String.trim(out)

      {out, code} ->
        Mix.raise("git #{Enum.join(args, " ")} failed (#{code}):\n#{out}")
    end
  end

  defp git(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end

  defp unique, do: System.unique_integer([:positive])
end
