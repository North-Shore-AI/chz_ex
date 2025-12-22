defmodule ChzEx.PrettyTest do
  use ExUnit.Case, async: true

  defmodule Config do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:count, :integer, default: 1)
      field(:secret, :string, default: "hidden", repr: false)
    end
  end

  test "formats chz structs without ANSI codes when colored is false" do
    config = %Config{name: "demo", count: 1, secret: "hidden"}
    output = ChzEx.Pretty.format(config, false)

    assert String.contains?(output, "Config(")
    assert String.contains?(output, "name=\"demo\"")
    assert String.contains?(output, "secret=...")
    refute String.contains?(output, "\e[")
  end
end
