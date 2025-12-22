defmodule ChzEx.Pretty do
  @moduledoc """
  Human-readable formatting for ChzEx structs.
  """

  alias ChzEx.{Field, Schema, Type}

  @doc """
  Format a ChzEx struct for display.
  """
  @spec format(any(), boolean()) :: String.t()
  def format(obj, colored \\ true) do
    do_format(obj, colored, %{})
  end

  # Uses a plain map for cycle detection to avoid Dialyzer opaque type issues with MapSet.
  defp do_format(obj, colored, seen) do
    space = " " <> " " <> " " <> " "

    cond do
      is_list(obj) ->
        format_list(obj, colored, space, seen)

      is_tuple(obj) ->
        obj |> Tuple.to_list() |> format_tuple(colored, space, seen)

      is_map(obj) and not Schema.chz?(obj) ->
        format_map(obj, colored, space, seen)

      Schema.chz?(obj) ->
        format_struct(obj, colored, space, seen)

      true ->
        inspect(obj)
    end
  end

  defp format_struct(obj, colored, space, seen) do
    if Map.has_key?(seen, obj) do
      "#<cycle #{Type.type_repr(obj.__struct__)}>"
    else
      format_struct_fields(obj, colored, space, Map.put(seen, obj, true))
    end
  end

  defp format_struct_fields(obj, colored, space, seen) do
    {bold, blue, grey, reset} = ansi_codes(colored)
    cls_name = Type.type_repr(obj.__struct__)
    out = [bold, cls_name, "(", reset, "\n"]
    fields = obj.__struct__.__chz_fields__()

    {non_default, defaulted} = split_fields(fields, obj, colored, space, grey, reset, seen, blue)

    out =
      out ++
        Enum.reverse(non_default) ++
        maybe_default_section(defaulted, space, bold, reset) ++
        [bold, ")", reset]

    IO.iodata_to_binary(out)
  end

  defp split_fields(fields, obj, colored, space, grey, reset, seen, blue) do
    fields
    |> Enum.sort_by(fn {name, _field} -> Atom.to_string(name) end)
    |> Enum.reduce({[], []}, fn {name, field}, {non_default, defaulted} ->
      value = Map.get(obj, name)
      val_str = field_repr(field, value, colored, space, grey, reset, seen)
      field_line = [space, blue, Atom.to_string(name), "=", reset, val_str, ",\n"]

      if default_match?(field, value) do
        {non_default, [field_line | defaulted]}
      else
        {[field_line | non_default], defaulted}
      end
    end)
  end

  defp ansi_codes(colored) do
    {
      ansi(IO.ANSI.bright(), colored),
      ansi(IO.ANSI.blue(), colored),
      ansi(IO.ANSI.light_black(), colored),
      ansi(IO.ANSI.reset(), colored)
    }
  end

  defp format_list(list, colored, space, seen) do
    if list == [] or Enum.all?(list, fn item -> not Schema.chz?(item) end) do
      inspect(list)
    else
      items =
        list
        |> Enum.map(&do_format(&1, colored, seen))
        |> Enum.map(&indent(&1, space))

      "[\n" <> space <> Enum.join(items, ",\n" <> space) <> ",\n]"
    end
  end

  defp format_tuple(list, colored, space, seen) do
    if list == [] or Enum.all?(list, fn item -> not Schema.chz?(item) end) do
      inspect(List.to_tuple(list))
    else
      items =
        list
        |> Enum.map(&do_format(&1, colored, seen))
        |> Enum.map(&indent(&1, space))

      "(\n" <> space <> Enum.join(items, ",\n" <> space) <> ",\n)"
    end
  end

  defp format_map(map, colored, space, seen) do
    if map == %{} or Enum.all?(map, fn {_k, v} -> not Schema.chz?(v) end) do
      inspect(map)
    else
      items =
        map
        |> Enum.map(fn {k, v} ->
          k_str = do_format(k, colored, seen) |> indent(space)
          v_str = do_format(v, colored, seen) |> indent(space)
          k_str <> ": " <> v_str
        end)

      "{\n" <> space <> Enum.join(items, ",\n" <> space) <> ",\n}"
    end
  end

  defp field_repr(%Field{repr: false}, _value, _colored, _space, _grey, _reset, _seen),
    do: "..."

  defp field_repr(%Field{repr: repr}, value, _colored, space, _grey, _reset, _seen)
       when is_function(repr, 1) do
    repr.(value)
    |> to_string()
    |> indent(space)
  end

  defp field_repr(%Field{repr: true}, value, colored, space, _grey, _reset, seen) do
    value
    |> do_format(colored, seen)
    |> indent(space)
  end

  defp field_repr(%Field{}, value, colored, space, _grey, _reset, seen) do
    value
    |> do_format(colored, seen)
    |> indent(space)
  end

  defp default_match?(%Field{} = field, value) do
    if Field.has_default?(field) do
      Field.get_default(field) == value
    else
      false
    end
  end

  defp maybe_default_section([], _space, _bold, _reset), do: []

  defp maybe_default_section(defaulted, space, bold, reset) do
    [
      space,
      bold,
      "# Fields where value matches default:",
      reset,
      "\n"
    ] ++ Enum.reverse(defaulted)
  end

  defp indent(value, space) do
    String.replace(value, "\n", "\n" <> space)
  end

  defp ansi(code, true), do: IO.iodata_to_binary(code)
  defp ansi(_code, false), do: ""
end
