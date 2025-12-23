defmodule ChzEx.ComputedTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint
  alias ChzEx.Blueprint.{Computed, Reference}

  defmodule ConfigWithComputed do
    use ChzEx.Schema

    chz_schema do
      field(:first_name, :string)
      field(:last_name, :string)

      field(:full_name, :string,
        munger: ChzEx.Munger.if_none(fn s -> "#{s.first_name} #{s.last_name}" end)
      )
    end
  end

  defmodule ComputedConfig do
    use ChzEx.Schema

    chz_schema do
      field(:a, :integer)
      field(:b, :integer)
      field(:sum, :integer)
    end
  end

  describe "Computed type" do
    test "computes value from other parameters" do
      computed = %Computed{
        sources: %{
          a: %Reference{ref: "a"},
          b: %Reference{ref: "b"}
        },
        compute: fn %{a: a, b: b} -> a + b end
      }

      {:ok, result} =
        Blueprint.new(ComputedConfig)
        |> Blueprint.apply(%{
          "a" => 10,
          "b" => 20,
          "sum" => computed
        })
        |> Blueprint.make()

      assert result.a == 10
      assert result.b == 20
      assert result.sum == 30
    end

    test "computed with string keys in sources" do
      computed = %Computed{
        sources: %{
          "x" => %Reference{ref: "a"},
          "y" => %Reference{ref: "b"}
        },
        compute: fn %{x: x, y: y} -> x * y end
      }

      {:ok, result} =
        Blueprint.new(ComputedConfig)
        |> Blueprint.apply(%{
          "a" => 5,
          "b" => 6,
          "sum" => computed
        })
        |> Blueprint.make()

      assert result.sum == 30
    end

    test "computed value is shown in help" do
      computed = %Computed{
        sources: %{a: %Reference{ref: "a"}},
        compute: fn _ -> 0 end
      }

      bp =
        Blueprint.new(ComputedConfig)
        |> Blueprint.apply(%{"sum" => computed})

      help = Blueprint.get_help(bp)
      assert help =~ "f(...)"
    end

    test "detects cycle in computed references" do
      # Create a cycle: a depends on b, b depends on a
      computed_a = %Computed{
        sources: %{b: %Reference{ref: "b"}},
        compute: fn %{b: b} -> b + 1 end
      }

      computed_b = %Computed{
        sources: %{a: %Reference{ref: "a"}},
        compute: fn %{a: a} -> a + 1 end
      }

      assert {:error, %ChzEx.Error{type: :cycle}} =
               Blueprint.new(ComputedConfig)
               |> Blueprint.apply(%{
                 "a" => computed_a,
                 "b" => computed_b,
                 "sum" => 0
               })
               |> Blueprint.make()
    end

    test "errors on invalid reference target" do
      computed = %Computed{
        sources: %{x: %Reference{ref: "nonexistent"}},
        compute: fn _ -> 0 end
      }

      assert {:error, %ChzEx.Error{type: :invalid_reference}} =
               Blueprint.new(ComputedConfig)
               |> Blueprint.apply(%{
                 "a" => 1,
                 "b" => 2,
                 "sum" => computed
               })
               |> Blueprint.make()
    end
  end

  describe "Computed with mungers" do
    test "munger can compute from other fields" do
      {:ok, result} =
        Blueprint.new(ConfigWithComputed)
        |> Blueprint.apply(%{
          "first_name" => "John",
          "last_name" => "Doe"
        })
        |> Blueprint.make()

      assert result.first_name == "John"
      assert result.last_name == "Doe"
      assert result.full_name == "John Doe"
    end
  end
end
