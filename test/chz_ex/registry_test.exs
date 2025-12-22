defmodule ChzEx.RegistryTest do
  use ExUnit.Case, async: false

  defmodule SampleModule do
  end

  setup do
    start_supervised!(ChzEx.Registry)
    :ok
  end

  describe "register/3" do
    test "registers module under namespace" do
      assert :ok = ChzEx.Registry.register(:test_ns, "sample", SampleModule)
      assert {:ok, SampleModule} = ChzEx.Registry.lookup(:test_ns, "sample")
    end
  end

  describe "lookup/2" do
    test "finds registered module" do
      :ok = ChzEx.Registry.register(:test_ns, "sample", SampleModule)
      assert {:ok, SampleModule} = ChzEx.Registry.lookup(:test_ns, "sample")
    end

    test "returns :error for unknown" do
      assert :error = ChzEx.Registry.lookup(:test_ns, "missing")
    end
  end

  describe "find_by_name/2" do
    test "searches all namespaces" do
      :ok = ChzEx.Registry.register(:one, "sample", SampleModule)
      assert {:ok, SampleModule} = ChzEx.Registry.find_by_name(:ignored, "sample")
    end
  end

  describe "register_module/1" do
    test "allows module for polymorphic use" do
      assert :ok = ChzEx.Registry.register_module(SampleModule)
      assert {:ok, SampleModule} = ChzEx.Registry.lookup_module("ChzEx.RegistryTest.SampleModule")
    end
  end

  describe "lookup_module/1" do
    test "finds registered module by string" do
      :ok = ChzEx.Registry.register_module(SampleModule)
      assert {:ok, SampleModule} = ChzEx.Registry.lookup_module("ChzEx.RegistryTest.SampleModule")
    end

    test "rejects unregistered modules" do
      assert :error = ChzEx.Registry.lookup_module("ChzEx.RegistryTest.MissingModule")
    end
  end
end
