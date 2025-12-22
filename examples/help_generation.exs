# Help generation example

defmodule Examples.HelpModel do
  use ChzEx.Schema

  chz_schema do
    field(:hidden_dim, :integer, default: 768, doc: "Hidden dimension")
    field(:num_layers, :integer, default: 12, doc: "Number of layers")
  end
end

defmodule Examples.HelpConfig do
  use ChzEx.Schema

  @moduledoc """
  Example configuration for help output.
  """

  chz_schema do
    field(:name, :string, doc: "Experiment name")
    field(:seed, :integer, default: 42, doc: "Random seed")
    embeds_one(:model, Examples.HelpModel)
  end
end

help = ChzEx.Blueprint.new(Examples.HelpConfig) |> ChzEx.Blueprint.get_help()
IO.puts(help)
