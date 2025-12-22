defmodule ChzEx.ReferenceTest do
  use ExUnit.Case, async: true

  alias ChzEx.Blueprint
  alias ChzEx.Blueprint.Reference

  defmodule BasicMain do
    use ChzEx.Schema

    chz_schema do
      field(:a, :string)
      field(:b, :string)
    end
  end

  defmodule HelpMain do
    use ChzEx.Schema

    chz_schema do
      field(:a, :string)
      field(:b, :string)
    end
  end

  defmodule InvalidMain do
    use ChzEx.Schema

    chz_schema do
      field(:a, :string)
      field(:b, :string)
    end
  end

  defmodule MultiInvalidMain do
    use ChzEx.Schema

    chz_schema do
      field(:a, :integer)
      field(:b, :integer)
      field(:c, :integer)
    end
  end

  defmodule C do
    use ChzEx.Schema

    chz_schema do
      field(:c, :integer)
    end
  end

  defmodule B do
    use ChzEx.Schema

    chz_schema do
      field(:b, :integer)
      embeds_one(:c, C)
    end
  end

  defmodule A do
    use ChzEx.Schema

    chz_schema do
      field(:a, :integer)
      embeds_one(:b, B)
    end
  end

  defmodule B2 do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
    end
  end

  defmodule A2 do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:b, B2)
    end
  end

  defmodule Main2 do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:a, A2)
    end
  end

  defmodule A3 do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
    end
  end

  defmodule Main3 do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string, default: "foo")
      embeds_one(:a, A3)
    end
  end

  defmodule MainSelf do
    use ChzEx.Schema

    chz_schema do
      field(:a, :integer)
    end
  end

  defmodule MainCycle do
    use ChzEx.Schema

    chz_schema do
      field(:a, :integer)
      field(:b, :integer)
    end
  end

  describe "references" do
    test "copies values between fields" do
      {:ok, obj} =
        BasicMain
        |> Blueprint.new()
        |> Blueprint.apply(%{"a" => "foo", "b" => Reference.new("a")})
        |> Blueprint.make()

      assert obj.a == "foo"
      assert obj.b == "foo"

      {:ok, obj2} =
        Blueprint.new(BasicMain)
        |> Blueprint.apply_from_argv(["a=foo", "b@=a"])
        |> elem(1)
        |> Blueprint.make()

      assert obj2.b == "foo"
    end

    test "help shows reference syntax" do
      help =
        Blueprint.new(HelpMain)
        |> Blueprint.apply(%{"a" => "foo", "b" => Reference.new("a")})
        |> Blueprint.get_help()

      assert help =~ "@=a"
    end

    test "errors for invalid reference target" do
      assert {:error, %ChzEx.Error{type: :invalid_reference, message: msg}} =
               Blueprint.new(InvalidMain)
               |> Blueprint.apply(%{"a" => "foo", "b" => Reference.new("c")})
               |> Blueprint.make()

      assert msg =~ "Invalid reference target"
    end

    test "multiple invalid references include suggestions" do
      assert {:error, %ChzEx.Error{message: msg}} =
               Blueprint.new(MultiInvalidMain)
               |> Blueprint.apply_from_argv(["a@=x", "b@=x", "c@=bb"])
               |> elem(1)
               |> Blueprint.make()

      assert msg =~ "Invalid reference target"
      assert msg =~ "Did you mean"
    end

    test "nested references work" do
      {:ok, obj} =
        Blueprint.new(A)
        |> Blueprint.apply_from_argv(["a@=b.b", "b.c.c@=a", "b.b=5"])
        |> elem(1)
        |> Blueprint.make()

      assert obj.a == 5
      assert obj.b.b == 5
      assert obj.b.c.c == 5
    end

    test "wildcard references propagate" do
      {:ok, obj} =
        Blueprint.new(Main2)
        |> Blueprint.apply_from_argv(["...name@=name", "name=foo"])
        |> elem(1)
        |> Blueprint.make()

      assert obj.name == "foo"
      assert obj.a.name == "foo"
      assert obj.a.b.name == "foo"
    end

    test "wildcard reference uses defaults" do
      {:ok, obj} =
        Blueprint.new(Main3)
        |> Blueprint.apply_from_argv(["...name@=name"])
        |> elem(1)
        |> Blueprint.make()

      assert obj.name == "foo"
      assert obj.a.name == "foo"
    end

    test "self reference requires default or errors" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               Blueprint.new(MainSelf)
               |> Blueprint.apply_from_argv(["a@=a"])
               |> elem(1)
               |> Blueprint.make()
    end

    test "cycle detection returns error" do
      assert {:error, %ChzEx.Error{type: :cycle}} =
               Blueprint.new(MainCycle)
               |> Blueprint.apply_from_argv(["a@=b", "b@=a"])
               |> elem(1)
               |> Blueprint.make()
    end
  end
end
