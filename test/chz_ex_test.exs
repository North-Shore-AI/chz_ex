defmodule ChzExTest do
  use ExUnit.Case, async: true

  defmodule InnerConfig do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer, default: 1)
    end
  end

  defmodule MainConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:count, :integer, default: 2)
      embeds_one(:inner, InnerConfig)
    end
  end

  describe "entrypoint/2" do
    test "parses argv and returns struct" do
      {:ok, config} = ChzEx.entrypoint(MainConfig, ["name=test", "count=3"])

      assert config.name == "test"
      assert config.count == 3
    end

    test "returns error tuple on failure" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               ChzEx.entrypoint(MainConfig, ["count=3"])
    end
  end

  describe "entrypoint!/2" do
    test "returns struct on success" do
      config = ChzEx.entrypoint!(MainConfig, ["name=test"])
      assert config.name == "test"
    end

    test "raises on failure" do
      assert_raise ChzEx.ConfigError, fn ->
        ChzEx.entrypoint!(MainConfig, ["count=3"])
      end
    end
  end

  describe "make/2" do
    test "creates struct from map" do
      {:ok, config} = ChzEx.make(MainConfig, %{"name" => "test"})
      assert config.name == "test"
      assert config.count == 2
    end
  end

  describe "make!/2" do
    test "creates struct or raises" do
      assert_raise ChzEx.ConfigError, fn ->
        ChzEx.make!(MainConfig, %{})
      end
    end
  end

  describe "is_chz?/1" do
    test "delegates to Schema" do
      assert ChzEx.is_chz?(MainConfig)
      assert ChzEx.is_chz?(%MainConfig{})
      refute ChzEx.is_chz?(String)
    end
  end

  describe "chz_fields/1" do
    test "returns field map" do
      fields = ChzEx.chz_fields(MainConfig)
      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :count)
    end
  end

  describe "replace/2" do
    test "updates fields via changeset" do
      {:ok, config} = ChzEx.make(MainConfig, %{"name" => "test"})
      {:ok, updated} = ChzEx.replace(config, %{count: 5})

      assert updated.count == 5
    end
  end

  describe "asdict/2" do
    test "converts to map" do
      {:ok, config} = ChzEx.make(MainConfig, %{"name" => "test"})
      assert %{:name => "test", :count => 2, :inner => %{value: 1}} = ChzEx.asdict(config)
    end

    test "recursive by default" do
      {:ok, config} = ChzEx.make(MainConfig, %{"name" => "test"})
      result = ChzEx.asdict(config)

      assert is_map(result.inner)
      assert result.inner.value == 1
    end

    test "shallow option" do
      {:ok, config} = ChzEx.make(MainConfig, %{"name" => "test"})
      result = ChzEx.asdict(config, shallow: true)

      assert match?(%InnerConfig{}, result.inner)
    end
  end
end
