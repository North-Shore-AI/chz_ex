defmodule ChzEx.MapSchemaTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint

  defmodule ConfigWithMapSchema do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:options, {:map_schema, %{timeout: :integer, retries: :integer}})
    end
  end

  defmodule ConfigWithOptionalFields do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)

      field(
        :settings,
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

  defmodule ConfigWithDefaultOptional do
    use ChzEx.Schema

    chz_schema do
      field(
        :config,
        {:map_schema,
         %{
           a: :integer,
           b: {:integer, :optional}
         }},
        default: %{a: 1}
      )
    end
  end

  describe "map_schema type" do
    test "expands map fields as parameters" do
      help = Blueprint.new(ConfigWithMapSchema) |> Blueprint.get_help()

      assert help =~ "options.timeout"
      assert help =~ "options.retries"
    end

    test "constructs map from expanded parameters" do
      {:ok, result} =
        Blueprint.new(ConfigWithMapSchema)
        |> Blueprint.apply(%{
          "name" => "test",
          "options.timeout" => 30,
          "options.retries" => 3
        })
        |> Blueprint.make()

      assert result.name == "test"
      assert result.options == %{timeout: 30, retries: 3}
    end

    test "casts string values for map fields" do
      {:ok, result} =
        Blueprint.new(ConfigWithMapSchema)
        |> Blueprint.apply(%{
          "name" => "test",
          "options.timeout" => %ChzEx.Blueprint.Castable{value: "30"},
          "options.retries" => %ChzEx.Blueprint.Castable{value: "3"}
        })
        |> Blueprint.make()

      assert result.options == %{timeout: 30, retries: 3}
    end

    test "returns error for missing required map fields" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               Blueprint.new(ConfigWithMapSchema)
               |> Blueprint.apply(%{"name" => "test", "options.timeout" => 30})
               |> Blueprint.make()
    end
  end

  describe "optional map fields" do
    test "required fields must be provided" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               Blueprint.new(ConfigWithOptionalFields)
               |> Blueprint.apply(%{
                 "name" => "test",
                 "settings.host" => "localhost"
                 # missing settings.port
               })
               |> Blueprint.make()
    end

    test "optional fields can be omitted" do
      {:ok, result} =
        Blueprint.new(ConfigWithOptionalFields)
        |> Blueprint.apply(%{
          "name" => "test",
          "settings.host" => "localhost",
          "settings.port" => 8080
        })
        |> Blueprint.make()

      assert result.settings == %{host: "localhost", port: 8080}
    end

    test "optional fields are included when provided" do
      {:ok, result} =
        Blueprint.new(ConfigWithOptionalFields)
        |> Blueprint.apply(%{
          "name" => "test",
          "settings.host" => "localhost",
          "settings.port" => 8080,
          "settings.ssl" => true,
          "settings.timeout" => 5000
        })
        |> Blueprint.make()

      assert result.settings == %{host: "localhost", port: 8080, ssl: true, timeout: 5000}
    end

    test "help shows optional marker for optional fields" do
      help = Blueprint.new(ConfigWithOptionalFields) |> Blueprint.get_help()

      # Required fields don't have optional marker
      assert help =~ "settings.host"
      assert help =~ "settings.port"
    end
  end

  describe "map_schema in type module" do
    test "type_repr displays map schema" do
      assert ChzEx.Type.type_repr({:map_schema, %{a: :integer}}) == "%{a: integer}"
    end

    test "type_repr displays complex map schema" do
      type = {:map_schema, %{host: {:string, :required}, port: {:integer, :optional}}}
      repr = ChzEx.Type.type_repr(type)

      assert repr =~ "host"
      assert repr =~ "port"
    end
  end
end
