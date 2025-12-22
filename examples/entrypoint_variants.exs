# Entrypoint variants example

defmodule Examples.RunConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    field(:count, :integer, default: 1)
  end
end

defmodule Examples.TuneConfig do
  use ChzEx.Schema

  chz_schema do
    field(:name, :string)
    field(:lr, :float, default: 0.01)
  end
end

defmodule Examples.Commands do
  use ChzEx.Schema

  chz_schema do
    field(:project, :string)
  end

  def __chz_commands__ do
    [
      {:train, "Train the model", [epochs: :integer]},
      {:eval, "Evaluate the model", [split: :string]}
    ]
  end

  def train(config, opts), do: {:train, config.project, opts[:epochs]}
  def eval(config, opts), do: {:eval, config.project, opts[:split]}
end

defmodule Examples.EntryVariants do
  def run_task(config) do
    {:nested, config.name, config.count}
  end

  def main(argv) do
    result =
      case argv do
        ["methods" | rest] ->
          ChzEx.CLI.with_error_handling(
            fn -> ChzEx.methods_entrypoint(Examples.Commands, rest) end,
            halt?: false
          )

        ["nested" | rest] ->
          ChzEx.CLI.with_error_handling(
            fn -> ChzEx.nested_entrypoint(&run_task/1, Examples.RunConfig, rest) end,
            halt?: false
          )

        _ ->
          commands = %{"run" => Examples.RunConfig, "tune" => Examples.TuneConfig}

          ChzEx.CLI.with_error_handling(
            fn -> ChzEx.dispatch_entrypoint(commands, argv) end,
            halt?: false
          )
      end

    case result do
      {:ok, value} ->
        IO.inspect(value, pretty: true)

      {:help, message} ->
        IO.puts(message)

      {:error, error} ->
        IO.puts(:stderr, "Error: #{ChzEx.Error.format(error)}")
    end
  end
end

Examples.EntryVariants.main(System.argv())
