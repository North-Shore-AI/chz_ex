# Advanced types example (v0.1.2 features)
# Demonstrates map schemas, heterogeneous tuples, and version suffixes

IO.puts("=== Map Schema Types ===\n")

defmodule Examples.ServerConfig do
  use ChzEx.Schema

  # Version suffix allows iteration tracking (the -v2 is ignored in hash validation)
  chz_schema version: "ba3a6f05-v2" do
    field(:name, :string)

    # Map schema with required and optional fields
    field(
      :connection,
      {:map_schema,
       %{
         host: {:string, :required},
         port: {:integer, :required},
         ssl: {:boolean, :optional},
         timeout: {:integer, :optional}
       }}
    )
  end
end

# Build with CLI-style args: connection.host=localhost connection.port=5432
{:ok, bp} =
  ChzEx.Blueprint.new(Examples.ServerConfig)
  |> ChzEx.Blueprint.apply_from_argv([
    "name=db_server",
    "connection.host=localhost",
    "connection.port=5432",
    "connection.ssl=true"
  ])

case ChzEx.Blueprint.make(bp) do
  {:ok, config} ->
    IO.puts("Server config:")
    IO.inspect(config.connection, label: "  connection")

  {:error, err} ->
    IO.puts("Error: #{ChzEx.Error.format(err)}")
end

IO.puts("\n=== Heterogeneous Tuple Types ===\n")

defmodule Examples.CoordinateConfig do
  use ChzEx.Schema

  chz_schema do
    field(:label, :string)
    # Tuple with different types at each position
    field(:coords, {:tuple, [:integer, :integer, :string]})
  end
end

# Build with indexed args: coords.0=10 coords.1=20 coords.2=north
{:ok, bp2} =
  ChzEx.Blueprint.new(Examples.CoordinateConfig)
  |> ChzEx.Blueprint.apply_from_argv([
    "label=waypoint",
    "coords.0=10",
    "coords.1=20",
    "coords.2=north"
  ])

case ChzEx.Blueprint.make(bp2) do
  {:ok, config} ->
    IO.puts("Coordinate config:")
    IO.inspect(config.coords, label: "  coords")
    {x, y, dir} = config.coords
    IO.puts("  Parsed: x=#{x}, y=#{y}, direction=#{dir}")

  {:error, err} ->
    IO.puts("Error: #{ChzEx.Error.format(err)}")
end

IO.puts("\n=== Type Representations ===\n")

IO.puts("Map schema: #{ChzEx.Type.type_repr({:map_schema, %{host: :string, port: :integer}})}")
IO.puts("Tuple: #{ChzEx.Type.type_repr({:tuple, [:integer, :integer, :string]})}")

IO.puts("\n=== Version Hash ===\n")

hash = ChzEx.Schema.version_hash(Examples.ServerConfig)
IO.puts("ServerConfig version hash: #{hash}")
