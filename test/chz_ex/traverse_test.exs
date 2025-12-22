defmodule ChzEx.TraverseTest do
  use ExUnit.Case, async: true

  defmodule Inner do
    use ChzEx.Schema

    chz_schema do
      field(:value, :integer)
    end
  end

  defmodule Outer do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:inner, Inner)
      field(:data, :map)
      field(:list, {:array, :integer})
    end
  end

  test "traverses nested chz values with paths" do
    config = %Outer{
      name: "root",
      inner: %Inner{value: 2},
      data: %{"a" => 1},
      list: [3]
    }

    paths =
      config
      |> ChzEx.Traverse.traverse()
      |> Enum.map(&elem(&1, 0))

    assert "" in paths
    assert "name" in paths
    assert "inner" in paths
    assert "inner.value" in paths
    assert "data" in paths
    assert "data.a" in paths
    assert "list" in paths
    assert "list.0" in paths
  end
end
