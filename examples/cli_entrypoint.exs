# CLI entrypoint example

defmodule Examples.CLIConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    field(:value, :integer, default: 0)
  end
end

defmodule Examples.CLI do
  def main(argv) do
    case ChzEx.entrypoint(Examples.CLIConfig, argv) do
      {:ok, config} ->
        IO.puts("CLI config:")
        IO.inspect(config, pretty: true)

      {:error, error} ->
        IO.puts(:stderr, "Error: #{ChzEx.Error.format(error)}")
        System.halt(1)
    end
  rescue
    e in [ChzEx.HelpException] ->
      IO.puts(e.message)
      System.halt(0)
  end
end

Examples.CLI.main(System.argv())
