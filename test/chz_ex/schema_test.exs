defmodule ChzEx.SchemaTest do
  use ExUnit.Case, async: true

  defmodule BasicSchema do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:count, :integer, default: 3)
    end
  end

  defmodule TypedSchema do
    use ChzEx.Schema

    chz_schema do
      field(:title, :string)
      field(:size, :integer)
      field(:rate, :float)
      field(:enabled, :boolean)
      field(:tags, {:array, :string})
    end
  end

  defmodule InnerSchema do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule OuterSchema do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:inner, InnerSchema)
    end
  end

  defmodule ManyOuterSchema do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_many(:items, InnerSchema)
    end
  end

  defmodule TypecheckSchema do
    use ChzEx.Schema

    chz_schema typecheck: true do
      field(:count, :integer)
    end
  end

  describe "chz_schema macro" do
    test "creates struct with fields" do
      struct = %BasicSchema{}

      assert Map.has_key?(struct, :name)
      assert Map.has_key?(struct, :count)
    end

    test "sets default values" do
      struct = %BasicSchema{}

      assert struct.count == 3
    end

    test "generates __chz_fields__/0" do
      fields = BasicSchema.__chz_fields__()

      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :count)
    end

    test "generates __chz__?/0 returning true" do
      assert BasicSchema.__chz__?()
    end

    test "generates changeset/2" do
      changeset = BasicSchema.changeset(%BasicSchema{}, %{"name" => "test"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end
  end

  describe "field types" do
    test "supports :string" do
      assert TypedSchema.__chz_fields__()[:title].type == :string
    end

    test "supports :integer" do
      assert TypedSchema.__chz_fields__()[:size].type == :integer
    end

    test "supports :float" do
      assert TypedSchema.__chz_fields__()[:rate].type == :float
    end

    test "supports :boolean" do
      assert TypedSchema.__chz_fields__()[:enabled].type == :boolean
    end

    test "supports {:array, :string}" do
      assert TypedSchema.__chz_fields__()[:tags].type == {:array, :string}
    end
  end

  describe "embeds_one" do
    test "embeds nested schema" do
      field = OuterSchema.__chz_fields__()[:inner]

      assert field.type == InnerSchema
      assert field.embed_type == :one
    end

    test "casts nested params" do
      changeset =
        OuterSchema.changeset(%OuterSchema{}, %{
          "name" => "test",
          "inner" => %{"value" => 5}
        })

      assert changeset.valid?
      {:ok, struct} = Ecto.Changeset.apply_action(changeset, :insert)
      assert struct.inner.value == 5
    end
  end

  describe "embeds_many" do
    test "embeds list of schemas" do
      field = ManyOuterSchema.__chz_fields__()[:items]

      assert field.type == InnerSchema
      assert field.embed_type == :many
    end

    test "casts list of params" do
      changeset =
        ManyOuterSchema.changeset(%ManyOuterSchema{}, %{
          "name" => "test",
          "items" => [%{"value" => 2}, %{"value" => 3}]
        })

      assert changeset.valid?
      {:ok, struct} = Ecto.Changeset.apply_action(changeset, :insert)
      assert Enum.map(struct.items, & &1.value) == [2, 3]
    end
  end

  describe "chz?/1" do
    test "true for chz module" do
      assert ChzEx.Schema.chz?(BasicSchema)
    end

    test "true for chz struct" do
      assert ChzEx.Schema.chz?(%BasicSchema{})
    end

    test "false for regular module" do
      refute ChzEx.Schema.chz?(String)
    end

    test "false for regular struct" do
      refute ChzEx.Schema.chz?(%{__struct__: Date})
    end
  end

  describe "schema versioning" do
    test "exposes version hash" do
      hash = TypecheckSchema.__chz_version__()
      assert is_binary(hash)
      assert byte_size(hash) == 8
    end

    test "raises on version mismatch" do
      assert_raise ArgumentError, fn ->
        Code.compile_string("""
        defmodule ChzEx.SchemaTest.BadVersion do
          use ChzEx.Schema

          chz_schema version: "deadbeef" do
            field(:name, :string)
          end
        end
        """)
      end
    end

    test "accepts version with suffix" do
      # Version suffixes allow iteration tracking without changing the hash
      # e.g., "a1b2c3d4-v2" or "a1b2c3d4-iteration3"
      hash = BasicSchema.__chz_version__()

      # This should compile without error
      [{mod, _}] =
        Code.compile_string("""
        defmodule ChzEx.SchemaTest.VersionWithSuffix do
          use ChzEx.Schema

          chz_schema version: "#{hash}-v2" do
            field(:name, :string)
            field(:count, :integer, default: 3)
          end
        end
        """)

      assert mod.__chz_version__() == hash
    end

    test "accepts version with numeric suffix" do
      hash = BasicSchema.__chz_version__()

      [{mod, _}] =
        Code.compile_string("""
        defmodule ChzEx.SchemaTest.VersionNumericSuffix do
          use ChzEx.Schema

          chz_schema version: "#{hash}-3" do
            field(:name, :string)
            field(:count, :integer, default: 3)
          end
        end
        """)

      assert mod.__chz_version__() == hash
    end
  end

  describe "typecheck option" do
    test "adds typecheck validators to changeset" do
      struct = %TypecheckSchema{count: "bad"}
      changeset = TypecheckSchema.changeset(struct, %{})

      refute changeset.valid?
      assert {msg, _} = changeset.errors[:count]
      assert String.contains?(msg, "Expected count")
    end
  end
end
