defmodule ElixirBaseline.DiffTest do
  use ExUnit.Case, async: true

  alias ElixirBaseline.Diff

  describe "counts/1" do
    test "counts what the template adds and removes" do
      diff = Diff.lines("a\nb\nc\n", "a\nx\ny\nc\n")

      assert Diff.counts(diff) == {2, 1}
    end

    test "counts a moved line once each way" do
      # the old measure called this four changes, being a set difference
      diff = Diff.lines("a\nb\n", "b\na\n")

      assert Diff.counts(diff) == {1, 1}
    end

    test "is nothing for a file that only differs by its final newline" do
      assert Diff.counts(Diff.lines("a\nb", "a\nb\n")) == {0, 0}
    end
  end

  describe "format/1" do
    test "marks each changed line and leaves the rest out" do
      diff = Diff.lines("keep\nold\n", "keep\nnew\n")

      assert Diff.format(diff) == "-old\n+new"
    end
  end
end
