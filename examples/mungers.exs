# Munger example

defmodule Examples.MungerConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    field(:display_name, :string, munger: ChzEx.Munger.attr_if_none(:name))

    field(:output_dir, :string,
      munger:
        ChzEx.Munger.if_none(fn struct ->
          "/experiments/#{struct.name}"
        end)
    )
  end
end

case ChzEx.entrypoint(Examples.MungerConfig) do
  {:ok, config} ->
    IO.puts("Munged config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{inspect(error)}")
    System.halt(1)
end
