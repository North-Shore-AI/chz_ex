# Type system and casting example

IO.puts("Type representations:")
IO.puts("  union: #{ChzEx.Type.type_repr({:union, [:integer, :string]})}")
IO.puts("  optional: #{ChzEx.Type.type_repr(ChzEx.Type.make_optional(:integer))}")
IO.puts("  mapset: #{ChzEx.Type.type_repr({:mapset, :string})}")

IO.puts("\nRuntime checks:")
IO.puts("  is_instance?(42, :integer): #{ChzEx.Type.is_instance?(42, :integer)}")

IO.puts(
  "  is_instance?([1, 2], {:array, :integer}): #{ChzEx.Type.is_instance?([1, 2], {:array, :integer})}"
)

IO.puts("\nCasting:")
IO.inspect(ChzEx.Cast.try_cast("12", :integer), label: "integer")
IO.inspect(ChzEx.Cast.try_cast("true", :boolean), label: "boolean")
IO.inspect(ChzEx.Cast.try_cast("a,b", {:array, :string}), label: "array")
IO.inspect(ChzEx.Cast.try_cast("a,b", {:mapset, :string}), label: "mapset")
IO.inspect(ChzEx.Cast.try_cast("2025-12-22", Date), label: "date")
IO.inspect(ChzEx.Cast.try_cast("~/data", :path), label: "path")

defmodule Examples.TypeSystemConfig do
  use ChzEx.Schema

  chz_schema typecheck: true do
    field(:count, :integer)
    field(:mode, :string, default: "fast")
  end
end

case ChzEx.make(Examples.TypeSystemConfig, %{"count" => 5}) do
  {:ok, config} ->
    IO.puts("\nConfig:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{ChzEx.Error.format(error)}")
    System.halt(1)
end
