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

  describe "is_chz?/1" do
    test "true for chz module" do
      assert ChzEx.Schema.is_chz?(BasicSchema)
    end

    test "true for chz struct" do
      assert ChzEx.Schema.is_chz?(%BasicSchema{})
    end

    test "false for regular module" do
      refute ChzEx.Schema.is_chz?(String)
    end

    test "false for regular struct" do
      refute ChzEx.Schema.is_chz?(%{__struct__: Date})
    end
  end
end
