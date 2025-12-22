defmodule ChzEx.Wildcard do
  @moduledoc """
  Wildcard pattern matching for argument keys.

  Patterns use `...` to match zero or more path segments.
  """

  @fuzzy_similarity 0.6

  @doc """
  Convert a wildcard key to a regex pattern.
  """
  def to_regex(key) when is_binary(key) do
    if String.ends_with?(key, "...") do
      raise ArgumentError, "Wildcard not allowed at end of key"
    end

    pattern =
      if String.starts_with?(key, "...") do
        key = String.replace_prefix(key, "...", "")
        parts = String.split(key, "...")
        escaped = Enum.map(parts, &Regex.escape/1)
        "(.*\\.)?" <> Enum.join(escaped, "\\.(.*\\.)?")
      else
        parts = String.split(key, "...")
        escaped = Enum.map(parts, &Regex.escape/1)
        Enum.join(escaped, "\\.(.*\\.)?")
      end

    Regex.compile!("^" <> pattern <> "$")
  end

  @doc """
  Check if a wildcard pattern matches a target string.
  """
  def matches?(pattern, target) when is_binary(pattern) and is_binary(target) do
    regex = to_regex(pattern)
    Regex.match?(regex, target)
  end

  @doc """
  Approximate match for error suggestions.
  Returns {score, suggested_key}.
  """
  def approximate(key, target) when is_binary(key) and is_binary(target) do
    if String.ends_with?(key, "...") do
      raise ArgumentError, "Wildcard not allowed at end of key"
    end

    tokens = pattern_tokens(key)
    target_parts = String.split(target, ".", trim: true)

    tokens_t = List.to_tuple(tokens)
    target_t = List.to_tuple(target_parts)
    {result, _memo} = do_approx_match(tokens_t, target_t, 0, 0, %{})
    {score, value} = result
    {score, Enum.join(value, "")}
  end

  defp pattern_tokens(key) do
    Regex.scan(~r/\.\.\.|[^.]+/, key)
    |> List.flatten()
  end

  defp do_approx_match(tokens, target, i, j, memo) do
    key = {i, j}

    case memo do
      %{^key => result} ->
        {result, memo}

      _ ->
        tokens_len = tuple_size(tokens)
        target_len = tuple_size(target)

        {result, memo_after} =
          cond do
            i == tokens_len and j == target_len ->
              {{1.0, []}, memo}

            i == tokens_len ->
              {{0.0, []}, memo}

            j == target_len ->
              {{0.0, []}, memo}

            elem(tokens, i) == "..." ->
              {with_wild, memo1} = do_approx_match(tokens, target, i, j + 1, memo)
              {without_wild, memo2} = do_approx_match(tokens, target, i + 1, j, memo1)

              {score, value} =
                if elem(with_wild, 0) * @fuzzy_similarity > elem(without_wild, 0) do
                  {score, value} = with_wild
                  {score * @fuzzy_similarity, value}
                else
                  without_wild
                end

              value =
                case value do
                  [] -> value
                  ["..." | _] -> value
                  _ -> ["..." | value]
                end

              {{score, value}, memo2}

            true ->
              part = elem(tokens, i)
              target_part = elem(target, j)
              ratio = String.jaro_distance(part, target_part)

              if ratio >= @fuzzy_similarity do
                {next, memo1} = do_approx_match(tokens, target, i + 1, j + 1, memo)
                {score, value} = next
                score = score * ratio

                value =
                  case value do
                    [] -> [target_part]
                    ["..." | _] -> [target_part | value]
                    _ -> ["#{target_part}." | value]
                  end

                {{score, value}, memo1}
              else
                {{0.0, []}, memo}
              end
          end

        {result, Map.put(memo_after, key, result)}
    end
  end
end
