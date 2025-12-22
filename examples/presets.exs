# Presets example

defmodule Examples.PresetModel do
  use ChzEx.Schema

  chz_schema do
    field(:hidden_dim, :integer, default: 768)
    field(:num_layers, :integer, default: 12)
    field(:num_heads, :integer, default: 12)
  end
end

defmodule Examples.PresetConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string, default: "experiment")
    embeds_one(:model, Examples.PresetModel)
  end
end

defmodule Examples.Presets do
  def small do
    ChzEx.Blueprint.new(Examples.PresetConfig)
    |> ChzEx.Blueprint.apply(
      %{
        "model.hidden_dim" => 256,
        "model.num_layers" => 6,
        "model.num_heads" => 8
      },
      layer_name: "preset:small"
    )
  end

  def medium do
    ChzEx.Blueprint.new(Examples.PresetConfig)
    |> ChzEx.Blueprint.apply(
      %{
        "model.hidden_dim" => 512,
        "model.num_layers" => 12,
        "model.num_heads" => 8
      },
      layer_name: "preset:medium"
    )
  end

  def large do
    ChzEx.Blueprint.new(Examples.PresetConfig)
    |> ChzEx.Blueprint.apply(
      %{
        "model.hidden_dim" => 1024,
        "model.num_layers" => 24,
        "model.num_heads" => 16
      },
      layer_name: "preset:large"
    )
  end
end

args =
  System.argv()
  |> Enum.reject(&(&1 == "--"))

{preset_name, rest} =
  case args do
    [name | tail] -> {name, tail}
    [] -> {"", []}
  end

preset =
  case preset_name do
    "small" -> Examples.Presets.small()
    "medium" -> Examples.Presets.medium()
    "large" -> Examples.Presets.large()
    _ -> ChzEx.Blueprint.new(Examples.PresetConfig)
  end

case ChzEx.Blueprint.apply_from_argv(preset, rest) do
  {:ok, blueprint} ->
    case ChzEx.Blueprint.make(blueprint) do
      {:ok, config} ->
        IO.puts("Preset config:")
        IO.inspect(config, pretty: true)

      {:error, error} ->
        IO.puts(:stderr, "Error: #{inspect(error)}")
        System.halt(1)
    end

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
