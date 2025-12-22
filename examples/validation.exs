# Validation example

defmodule Examples.ValidationConfig do
  use ChzEx.Schema

  chz_schema do
    field(:value, :integer,
      validator: [
        ChzEx.Validator.gt(0),
        ChzEx.Validator.lt(100)
      ]
    )
  end

  @chz_validate :check_value
  def check_value(struct) do
    if struct.value == 13 do
      {:error, :value, "unlucky value"}
    else
      :ok
    end
  end
end

case ChzEx.entrypoint(Examples.ValidationConfig) do
  {:ok, config} ->
    IO.puts("Validated config:")
    IO.inspect(config, pretty: true)

  {:error, error} ->
    IO.puts(:stderr, "Error: #{ChzEx.Error.format(error)}")
    System.halt(1)
end
