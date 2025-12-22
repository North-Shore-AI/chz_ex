# Serialization and traversal example

defmodule Examples.SerialLayer do
  use ChzEx.Schema

  chz_schema do
    field(:kind, :string, default: "dense")
    field(:units, :integer, default: 128)
  end
end

defmodule Examples.SerialModel do
  use ChzEx.Schema

  chz_schema do
    field(:hidden_dim, :integer, default: 256)
    field(:dropout, :float, default: 0.1)
  end
end

defmodule Examples.SerialConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    field(:tags, {:array, :string}, default_factory: fn -> [] end)
    embeds_one(:model, Examples.SerialModel)
    embeds_many(:layers, Examples.SerialLayer)
  end
end

args = %{
  "name" => "roundtrip",
  "tags" => ["blue", "roundtrip"],
  "model.hidden_dim" => 512,
  "model.dropout" => 0.25,
  "layers.0.kind" => "conv",
  "layers.0.units" => 64,
  "layers.1.kind" => "dense",
  "layers.1.units" => 128
}

blueprint =
  Examples.SerialConfig
  |> ChzEx.Blueprint.new()
  |> ChzEx.Blueprint.apply(args)

case ChzEx.Blueprint.make(blueprint) do
  {:ok, config} ->
    IO.puts("Pretty config:")
    IO.puts(ChzEx.Pretty.format(config, false))

    IO.puts("\nTraverse sample:")

    config
    |> ChzEx.Traverse.traverse()
    |> Enum.take(8)
    |> Enum.each(fn {path, value} ->
      IO.puts("  #{path} => #{inspect(value)}")
    end)

    IO.puts("\nBlueprint values:")
    values = ChzEx.Serialize.to_blueprint_values(config)
    IO.inspect(values)

    IO.puts("\nArgv roundtrip:")
    argv = ChzEx.Blueprint.Serialize.to_argv(blueprint)
    IO.inspect(argv)

    case ChzEx.Blueprint.new(Examples.SerialConfig)
         |> ChzEx.Blueprint.apply_from_argv(argv) do
      {:ok, bp2} ->
        case ChzEx.Blueprint.make(bp2) do
          {:ok, roundtrip} ->
            IO.puts("\nRoundtrip matches: #{roundtrip == config}")

          {:error, error} ->
            IO.puts(:stderr, "Roundtrip error: #{inspect(error)}")
        end

      {:error, error} ->
        IO.puts(:stderr, "Argv apply error: #{inspect(error)}")
    end

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
