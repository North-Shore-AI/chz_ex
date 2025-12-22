defmodule ChzExTest do
  use ExUnit.Case
  doctest ChzEx

  test "greets the world" do
    assert ChzEx.hello() == :world
  end
end
