# Reference example

defmodule Examples.ReferenceConfig do
  use ChzEx.Schema

  chz_schema do
    field(:base_dim, :integer, default: 768)
    field(:hidden_dim, :integer)
    field(:ff_dim, :integer)
  end
end

blueprint =
  Examples.ReferenceConfig
  |> ChzEx.Blueprint.new()
  |> ChzEx.Blueprint.apply(%{
    "hidden_dim" => ChzEx.Blueprint.Reference.new("base_dim"),
    "ff_dim" => %ChzEx.Blueprint.Computed{
      sources: %{"hd" => ChzEx.Blueprint.Reference.new("hidden_dim")},
      compute: fn %{hd: hd} -> hd * 4 end
    }
  })

case ChzEx.Blueprint.make(blueprint) do
  {:ok, config} ->
    IO.puts("Reference config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
