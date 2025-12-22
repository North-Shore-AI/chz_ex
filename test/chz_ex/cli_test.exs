defmodule ChzEx.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  defmodule CommandConfig do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
    end
  end

  defmodule Commands do
    use ChzEx.Schema

    chz_schema do
      field(:name, :string)
    end

    def __chz_commands__ do
      [
        {:launch, "Launch job", [cluster: :string]},
        {:status, "Show status", []}
      ]
    end

    def launch(config, opts) do
      {config.name, Keyword.fetch!(opts, :cluster)}
    end

    def status(config) do
      {:status, config.name}
    end
  end

  describe "nested_entrypoint/3" do
    test "returns function result" do
      result =
        ChzEx.nested_entrypoint(fn config -> {:ok, config.name} end, CommandConfig, [
          "name=test"
        ])

      assert {:ok, {:ok, "test"}} = result
    end

    test "propagates entrypoint errors" do
      assert {:error, %ChzEx.Error{type: :missing_required}} =
               ChzEx.nested_entrypoint(fn _ -> :ok end, CommandConfig, [])
    end
  end

  describe "dispatch_entrypoint/2" do
    test "dispatches to selected command" do
      targets = %{"run" => CommandConfig}

      assert {:ok, %CommandConfig{name: "job"}} =
               ChzEx.dispatch_entrypoint(targets, ["run", "name=job"])
    end

    test "raises help for missing command" do
      assert_raise ChzEx.HelpError, fn ->
        ChzEx.dispatch_entrypoint(%{"run" => CommandConfig}, [])
      end
    end
  end

  describe "methods_entrypoint/2" do
    test "builds config and passes method args" do
      assert {:ok, {"job", "owl"}} =
               ChzEx.methods_entrypoint(Commands, ["launch", "name=job", "cluster=owl"])
    end

    test "dispatches to arity-1 methods" do
      assert {:ok, {:status, "job"}} =
               ChzEx.methods_entrypoint(Commands, ["status", "name=job"])
    end
  end

  describe "with_error_handling/1" do
    test "returns value on success" do
      assert :ok = ChzEx.CLI.with_error_handling(fn -> {:ok, :ok} end, halt?: false)
    end

    test "prints help without halting in tests" do
      output =
        capture_io(fn ->
          assert {:help, _} =
                   ChzEx.CLI.with_error_handling(
                     fn -> raise ChzEx.HelpError, message: "help text" end,
                     halt?: false
                   )
        end)

      assert output =~ "help text"
    end

    test "prints errors without halting in tests" do
      error = %ChzEx.Error{type: :missing_required, path: "name"}

      output =
        capture_io(:stderr, fn ->
          assert {:error, ^error} =
                   ChzEx.CLI.with_error_handling(fn -> {:error, error} end, halt?: false)
        end)

      assert output =~ "Missing required"
    end
  end
end
