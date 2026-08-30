defmodule ElixirBaseline.Patch do
  @moduledoc """
  Corrects one setting in a file this project does not own outright.

  Only the setting's own bytes are replaced. The file is parsed, never
  evaluated.
  """

  @type patch :: {:line_length, pos_integer}
  @type result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Returns every patched file of a resolved repo, keyed by its path in that repo.

  One `.formatter.exs` per project, since `import_deps` cannot carry
  `line_length`.
  """
  @spec files(map) :: %{String.t() => [patch]}
  def files(repo) do
    Map.new(repo.projects, fn project ->
      {destination(project.path), [{:line_length, project.line_length}]}
    end)
  end

  @doc """
  Applies every patch to a file's contents, in order.

  Each patch is read back out of the result, so one that does not take returns
  an error rather than a broken file.
  """
  @spec apply([patch], String.t()) :: result
  def apply(patches, contents) do
    Enum.reduce_while(patches, {:ok, contents}, fn patch, {:ok, source} ->
      case one(patch, source) do
        {:ok, patched} -> {:cont, {:ok, patched}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp destination("."), do: ".formatter.exs"
  defp destination(path), do: Path.join(path, ".formatter.exs")

  defp one({:line_length, length} = patch, source) do
    with {:ok, list} <- settings(source),
         {:ok, patched} <- set(list, source, length) do
      verify(patch, patched)
    end
  end

  defp verify({:line_length, length} = patch, source) do
    with {:ok, list} <- settings(source) do
      case value(pairs(list)) do
        {:ok, ^length, _range} ->
          {:ok, source}

        _other ->
          {:error, "#{inspect(patch)} did not take; the file is left alone"}
      end
    end
  end

  defp set(list, source, length) do
    case value(pairs(list)) do
      {:ok, ^length, _range} -> {:ok, source}
      {:ok, _other, range} -> {:ok, replace(source, range, length)}
      :absent -> insert(list, source, length)
      :unreadable -> {:error, "`line_length` is not a literal integer"}
    end
  end

  defp replace(source, range, length) do
    Sourceror.patch_string(source, [%{range: range, change: to_string(length)}])
  end

  defp insert(list, source, length) do
    case pairs(list) do
      [] ->
        {:error, "the settings list is empty; add `line_length` by hand"}

      pairs ->
        {:ok, splice(list, List.last(pairs), source, length)}
    end
  end

  defp splice(list, last, source, length) do
    at = Sourceror.get_range(last)
    point = %Sourceror.Range{start: at.end, end: at.end}
    change = separator(list, at) <> "line_length: #{length}"

    Sourceror.patch_string(source, [%{range: point, change: change}])
  end

  defp separator(list, last) do
    if Sourceror.get_range(list).end[:line] == last.end[:line] do
      ", "
    else
      ",\n"
    end
  end

  defp settings(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> list(ast)
      {:error, _reason} -> {:error, "the file does not parse"}
    end
  end

  # The file evaluates to its last expression, which a repo with a DSL puts
  # below its `locals_without_parens` bindings.
  defp list({:__block__, _meta, [pairs]} = list) when is_list(pairs) do
    {:ok, list}
  end

  defp list({:__block__, _meta, [_ | _] = expressions}) do
    case List.last(expressions) do
      {:__block__, _meta, [pairs]} = list when is_list(pairs) -> {:ok, list}
      _other -> {:error, "the file does not end in a settings list"}
    end
  end

  defp list(_other), do: {:error, "the file does not end in a settings list"}

  defp pairs({:__block__, _meta, [pairs]}), do: pairs

  # Top-level pairs only; a nested `line_length` belongs to something else.
  defp value(settings) do
    Enum.find_value(settings, :absent, fn
      {{:__block__, _, [:line_length]}, value} -> read(value)
      _pair -> nil
    end)
  end

  defp read({:__block__, _meta, [length]} = node) when is_integer(length) do
    {:ok, length, Sourceror.get_range(node)}
  end

  defp read(_node), do: :unreadable
end
