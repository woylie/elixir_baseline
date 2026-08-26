defmodule Mix.Tasks.Baseline.Pr do
  @shortdoc "Opens a pull request per repo whose Credo config has drifted"

  @moduledoc """
  Opens one pull request per configured repo whose `.credo.exs` differs.

  Each repo is cloned shallowly into a temporary directory, so no local checkout
  is needed and nothing you are working on is touched. Repos that already match
  are not cloned at all.

  A re-run updates the open pull request rather than opening a second one.

  ## Command line options

    * `--repo` - update only this repo. May be given more than once.
    * `--config` - path to the config. Defaults to `.baseline.exs`.
  """

  use Mix.Task

  alias ElixirBaseline.Check
  alias ElixirBaseline.Config
  alias ElixirBaseline.Options
  alias ElixirBaseline.Render

  @switches [repo: :keep, config: :string]

  @branch "baseline/credo"
  @message "update credo config from elixir_baseline"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    specs = Config.repos(Options.repos(opts))
    if specs == [], do: Mix.raise("no configured repos matched")

    results =
      for spec <- specs do
        IO.write("#{spec.name}: ")
        outcome = propose(spec)
        Mix.shell().info(line(outcome))
        {spec.name, outcome}
      end

    failed = for {name, {:error, _reason}} <- results, do: name
    if failed != [], do: Mix.raise("could not read #{Enum.join(failed, ", ")}")
  end

  defp line(:unchanged), do: "unchanged"
  defp line(:up_to_date), do: "up to date"
  defp line({:pull_request, url}), do: url
  defp line({:error, reason}), do: "error -- #{reason}"

  defp propose(spec) do
    case Check.Credo.run(spec) do
      :ok -> :unchanged
      {:error, reason} -> {:error, reason}
      _drifted -> update(spec)
    end
  end

  defp update(spec) do
    dir = Path.join(System.tmp_dir!(), "baseline-#{spec.name}-#{unique()}")

    try do
      IO.write("cloning... ")
      clone!(spec, dir)
      git!(dir, ["switch", "--quiet", "-c", @branch])
      File.write!(Path.join(dir, ".credo.exs"), Render.credo(spec))
      git!(dir, ["add", ".credo.exs"])
      git!(dir, ["commit", "--quiet", "-m", @message])
      IO.write("pushing... ")
      publish(dir)
    after
      File.rm_rf!(dir)
    end
  end

  defp publish(dir) do
    git(dir, [
      "fetch",
      "--quiet",
      "--depth",
      "1",
      "origin",
      "+refs/heads/#{@branch}:refs/remotes/origin/#{@branch}"
    ])

    case git(dir, ["rev-parse", "origin/#{@branch}^{tree}"]) do
      nil ->
        git!(dir, ["push", "--quiet", "origin", @branch])
        {:pull_request, pull_request(dir)}

      remote_tree ->
        if remote_tree == git!(dir, ["rev-parse", "HEAD^{tree}"]) do
          :up_to_date
        else
          force_push!(dir)
          {:pull_request, pull_request(dir)}
        end
    end
  end

  defp force_push!(dir) do
    sha = git!(dir, ["rev-parse", "origin/#{@branch}"])
    lease = "--force-with-lease=#{@branch}:#{sha}"

    git!(dir, ["push", "--quiet", lease, "origin", @branch])
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
