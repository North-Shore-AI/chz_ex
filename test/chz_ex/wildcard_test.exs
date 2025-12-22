defmodule ChzEx.WildcardTest do
  use ExUnit.Case, async: true

  alias ChzEx.Wildcard

  describe "to_regex/1" do
    test "prefix wildcard ...key" do
      regex = Wildcard.to_regex("...n_layers")
      assert Regex.match?(regex, "n_layers")
      assert Regex.match?(regex, "model.n_layers")
      assert Regex.match?(regex, "a.b.n_layers")
      refute Regex.match?(regex, "n_layers_extra")
    end

    test "infix wildcard a...b" do
      regex = Wildcard.to_regex("model...size")
      assert Regex.match?(regex, "model.size")
      assert Regex.match?(regex, "model.layer.size")
      refute Regex.match?(regex, "other.size")
    end

    test "multiple wildcards ...a...b" do
      regex = Wildcard.to_regex("...layer...dim")
      assert Regex.match?(regex, "layer.dim")
      assert Regex.match?(regex, "model.layer.hidden.dim")
    end

    test "no wildcard returns exact match" do
      regex = Wildcard.to_regex("model.layers")
      assert Regex.match?(regex, "model.layers")
      refute Regex.match?(regex, "model.layers.extra")
    end

    test "errors on trailing wildcard" do
      assert_raise ArgumentError, fn ->
        Wildcard.to_regex("model...")
      end
    end
  end

  describe "matches?/2" do
    test "exact match" do
      assert Wildcard.matches?("model.layers", "model.layers")
      refute Wildcard.matches?("model.layers", "model.layers.extra")
    end

    test "prefix wildcard matches" do
      assert Wildcard.matches?("...n_layers", "model.n_layers")
    end

    test "nested path matches" do
      assert Wildcard.matches?("model...dim", "model.layer.hidden.dim")
    end
  end

  describe "approximate/2" do
    test "high score for similar keys" do
      {score, _} = Wildcard.approximate("n_layer", "n_layers")
      assert score > 0.5
    end

    test "returns suggestion string" do
      {_score, suggestion} = Wildcard.approximate("n_layer", "n_layers")
      assert suggestion =~ "n_layers"
    end

    test "low score for different keys" do
      {score, _} = Wildcard.approximate("completely_different", "n_layers")
      assert score < 0.3
    end
  end
end
