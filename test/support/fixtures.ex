defmodule ChzEx.Test.Fixtures do
  @moduledoc false

  defmodule SimpleConfig do
    @moduledoc false
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      field(:value, :integer, default: 0)
    end
  end

  defmodule InnerConfig do
    @moduledoc false
    use ChzEx.Schema

    chz_schema do
      field(:x, :integer, default: 0)
      field(:y, :integer, default: 0)
    end
  end

  defmodule NestedConfig do
    @moduledoc false
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
      embeds_one(:inner, InnerConfig)
    end
  end
end
