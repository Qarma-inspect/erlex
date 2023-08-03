defmodule Erlex do
  @moduledoc """
  Convert Erlang style structs and error messages to equivalent Elixir.

  Lexes and parses the Erlang output, then runs through pretty
  printer.

  ## Usage

  Invoke `Erlex.pretty_print/1` wuth the input string.

  ```elixir
  iex> str = ~S"('Elixir.Plug.Conn':t(),binary() | atom(),'Elixir.Keyword':t() | map()) -> 'Elixir.Plug.Conn':t()"
  iex> Erlex.pretty_print(str)
  (Plug.Conn.t(), binary() | atom(), Keyword.t() | map()) :: Plug.Conn.t()
  ```

  While the lion's share of the work is done via invoking
  `Erlex.pretty_print/1`, other higher order functions exist for further
  formatting certain messages by running through the Elixir formatter.
  Because we know the previous example is a type, we can invoke the
  `Erlex.pretty_print_contract/1` function, which would format that
  appropriately for very long lines.

  ```elixir
  iex> str = ~S"('Elixir.Plug.Conn':t(),binary() | atom(),'Elixir.Keyword':t() | map(), map() | atom(), non_neg_integer(), binary(), binary(), binary(), binary(), binary()) -> 'Elixir.Plug.Conn':t()"
  iex> Erlex.pretty_print_contract(str)
  (
    Plug.Conn.t(),
    binary() | atom(),
    Keyword.t() | map(),
    map() | atom(),
    non_neg_integer(),
    binary(),
    binary(),
    binary(),
    binary(),
    binary()
  ) :: Plug.Conn.t()
  ```
  """

  defp lex(str) do
    try do
      {:ok, tokens, _} = :lexer.string(str)
      tokens
    rescue
      _ ->
        throw({:error, :lexing, str})
    end
  end

  defp parse(tokens) do
    try do
      {:ok, [first | _]} = :parser.parse(tokens)
      first
    rescue
      _ ->
        throw({:error, :parsing, tokens})
    end
  end

  defp format(code) do
    try do
      Code.format_string!(code)
    rescue
      _ ->
        throw({:error, :formatting, code})
    end
  end

  @spec pretty_print_infix(infix :: String.t()) :: String.t()
  def pretty_print_infix('=:='), do: "==="
  def pretty_print_infix('=/='), do: "!=="
  def pretty_print_infix('/='), do: "!="
  def pretty_print_infix('=<'), do: "<="
  def pretty_print_infix(infix), do: to_string(infix)

  @spec pretty_print(str :: String.t()) :: String.t()
  def pretty_print(str) do
    parsed =
      str
      |> to_charlist()
      |> lex()
      |> parse()

    try do
      do_pretty_print(parsed)
    rescue
      _ ->
        throw({:error, :pretty_printing, parsed})
    end
  end

  @spec pretty_print_diff(expected :: String.t(), actual :: String.t()) :: String.t()
  def pretty_print_diff(expected, actual) do
    parsed_expected =
      expected
      |> to_charlist()
      |> lex()
      |> parse()

    parsed_actual =
      actual
      |> to_charlist()
      |> lex()
      |> parse()

    case {parsed_expected, parsed_actual} do
      {{:map, expected_entries}, {:map, actual_entries}} ->
        expected_struct = struct_from_entries(expected_entries)
        actual_struct = struct_from_entries(actual_entries)

        if actual_struct == expected_struct do
          invalid_entries =
            parsed_expected
            |> find_invalid_entries(parsed_actual)
            |> format_invalid_entries()

          """

          Mismatched fields:
          #{invalid_entries}
          """
        else
          ""
        end

      {{:tuple, expected_entries}, {:tuple, actual_entries}} ->
        expected_length = length(expected_entries)
        actual_length = length(actual_entries)

        if expected_length == actual_length do
          invalid_entries =
            parsed_expected
            |> find_invalid_entries(parsed_actual)
            |> format_invalid_entries()

          """

          Mismatched fields:
          #{invalid_entries}
          """
        else
          """

          Expected tuple size is #{expected_length}, got one of size #{actual_length}.
          """
        end

      _ ->
        ""
    end
  end

  defp find_invalid_entries({:map, expected_entries}, {:map, actual_entries}) do
    expected_struct = struct_from_entries(expected_entries)
    actual_struct = struct_from_entries(actual_entries)

    if expected_struct == actual_struct do
      unexpected_entries = find_unexpected_entries(expected_entries, actual_entries)
      invalid_entries = Enum.flat_map(expected_entries, &find_invalid_map_entries(&1, actual_entries))

      invalid_entries ++ unexpected_entries
    else
      [{[], expected_struct, actual_struct}]
    end
  end

  defp find_invalid_entries({:tuple, expected_entries}, {:tuple, actual_entries}) do
    expected_length = length(expected_entries)
    actual_length = length(actual_entries)

    if expected_length == actual_length do
      expected_entries
      |> Enum.zip(actual_entries)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{expected_entry, actual_entry}, index} ->
        expected_entry
        |> find_invalid_entries(actual_entry)
        |> prepend_key(index)
      end)
    else
      [{[], :mismatched_tuple_size, expected_length, actual_length}]
    end
  end

  defp find_invalid_entries(expected, actual) do
    if matching_type?(expected, actual) do
      []
    else
      [{[], do_shallow_pretty_print(expected), do_shallow_pretty_print(actual)}]
    end
  end

  defp find_invalid_map_entries(expected_entry, actual_entries) do
    case expected_entry do
      {:map_entry, {:atom, '\'__struct__\''}, {:atom, _struct_name}} ->
        []

      {:map_entry, expected_key, expected_value} ->
        key = to_atom(expected_key)

        case find_entry_value(actual_entries, expected_key) do
          {:error, :not_found} ->
            [{[key], :not_found}]

          actual_value ->
            expected_value
            |> find_invalid_entries(actual_value)
            |> prepend_key(key)
        end
    end
  end

  defp prepend_key(invalid_entries_list, key) do
    Enum.map(invalid_entries_list, fn
      {keys, expected, actual} ->
        {[key | keys], expected, actual}

      {keys, :not_found} ->
        {[key | keys], :not_found}

      {keys, :unexpected} ->
        {[key | keys], :unexpected}

      {keys, :mismatched_tuple_size, expected_length, actual_length} ->
        {[key | keys], :mismatched_tuple_size, expected_length, actual_length}
    end)
  end

  defp struct_from_entries(entries) do
    entries
    |> Enum.find(fn
        {:map_entry, {:atom, '\'__struct__\''}, {:atom, _}} -> true
        _ -> false
      end)
    |> case do
      nil ->
        nil

      {:map_entry, {:atom, '\'__struct__\''}, {:atom, name}} ->
        name
        |> List.to_string()
        |> String.trim("'")
    end
  end

  defp find_entry_value(entries, key) do
    entries
    |> Map.new(fn {:map_entry, key_type, value_type} -> {key_type, value_type} end)
    |> Map.get(key, {:error, :not_found})
  end

  defp to_atom({:atom, atom_name}) do
    atom_name
    |> to_string()
    |> String.slice(1..-2)
    |> String.to_atom()
  end

  defp find_unexpected_entries(expected_entries, actual_entries) do
    actual_entries
    |> Enum.flat_map(fn {:map_entry, actual_key, _actual_value} ->
      case find_entry_value(expected_entries, actual_key) do
        {:error, :not_found} -> [{[to_atom(actual_key)], :unexpected}]
        _ -> []
      end
    end)
  end

  defp matching_type?({:atom, expected_atom}, {:atom, actual_atom}) do
    expected_atom == actual_atom
  end

  defp matching_type?({:type_list, ['b', 'i', 'n', 'a', 'r', 'y'], {:list, :paren, []}}, actual_type) do
    case actual_type do
      {:binary, [{:binary_part, {:any}, {:int, _}}]} -> true
      {:type_list, ['b', 'i', 'n', 'a', 'r', 'y'], {:list, :paren, []}} -> true
      _ -> false
    end
  end

  defp matching_type?({:type_list, ['f', 'l', 'o', 'a', 't'], {:list, :paren, []}}, actual_type) do
    case actual_type do
      {:type_list, ['f', 'l', 'o', 'a', 't'], {:list, :paren, []}} -> true
      _ -> false
    end
  end

  defp matching_type?({:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}}, actual_type) do
    case actual_type do
      {:atom, atom} when is_list(atom) -> true
      _ -> false
    end
  end

  defp matching_type?({:tuple, expected_tuple}, {:tuple, actual_tuple}) when length(expected_tuple) == length(actual_tuple) do
    expected_tuple
    |> Enum.zip(actual_tuple)
    |> Enum.all?(fn {expected_type, actual_type} -> matching_type?(expected_type, actual_type) end)
  end

  defp matching_type?(_expected_type, _actual_type) do
    false
  end

  defp format_invalid_entries(invalid_entries) do
    invalid_entries
    |> Enum.map(fn
      {keys, expected, actual} ->
        "#{inspect(keys)}: expected #{inspect(expected)}, got #{inspect(actual)}"

      {keys, :not_found} ->
        "#{inspect(keys)}: not found"

      {keys, :unexpected} ->
        "#{inspect(keys)}: unexpected key"

      {keys, :mismatched_tuple_size, expected_size, actual_size} ->
        "#{inspect(keys)}: expected tuple size is #{expected_size}, got one of size #{actual_size}"
    end)
    |> Enum.join("\n")
  end

  @spec shallow_pretty_print_type(type :: String.t()) :: String.t()
  def shallow_pretty_print_type(type) do
    prefix = "@spec a("
    suffix = ") :: :ok\ndef a() do\n  :ok\nend"
    indented_suffix = ") ::\n        :ok\ndef a() do\n  :ok\nend"
    pretty = shallow_pretty_print(type)

    """
    @spec a(#{pretty}) :: :ok
    def a() do
      :ok
    end
    """
    |> format()
    |> Enum.join("")
    |> String.trim_leading(prefix)
    |> String.trim_trailing(suffix)
    |> String.trim_trailing(indented_suffix)
    |> String.replace("\n      ", "\n")
  end

  defp shallow_pretty_print(str) do
    parsed =
      str
      |> to_charlist()
      |> lex()
      |> parse()

    try do
      do_shallow_pretty_print(parsed)
    rescue
      _ ->
        throw({:error, :pretty_printing, parsed})
    end
  end

  defp do_shallow_pretty_print({:map, map_keys}) do
    case struct_parts(map_keys) do
      %{name: name} -> "%#{name}{}"
    end
  end

  defp do_shallow_pretty_print({:tuple, _tuple_items}) do
    "tuple()"
  end

  defp do_shallow_pretty_print(parsed) do
    do_pretty_print(parsed)
  end

  @spec pretty_print_pattern(pattern :: String.t()) :: String.t()
  def pretty_print_pattern('pattern ' ++ rest) do
    pretty_print_type(rest)
  end

  def pretty_print_pattern(pattern) do
    pretty_print_type(pattern)
  end

  @spec pretty_print_contract(
          contract :: String.t(),
          module :: String.t(),
          function :: String.t()
        ) :: String.t()
  def pretty_print_contract(contract, module, function) do
    [head | tail] =
      contract
      |> to_string()
      |> String.split(";")

    head =
      head
      |> String.trim_leading(to_string(module))
      |> String.trim_leading(":")
      |> String.trim_leading(to_string(function))

    [head | tail]
    |> Enum.join(";")
    |> pretty_print_contract()
  end

  @spec pretty_print_contract(contract :: String.t()) :: String.t()
  def pretty_print_contract(contract) do
    [head | tail] =
      contract
      |> to_string()
      |> String.split(";")

    if Enum.empty?(tail) do
      do_pretty_print_contract(head)
    else
      joiner = "Contract head:\n"

      joiner <> Enum.map_join([head | tail], "\n\n" <> joiner, &do_pretty_print_contract/1)
    end
  end

  defp do_pretty_print_contract(contract) do
    prefix = "@spec a"
    suffix = "\ndef a() do\n  :ok\nend"
    pretty = pretty_print(contract)

    """
    @spec a#{pretty}
    def a() do
      :ok
    end
    """
    |> format()
    |> Enum.join("")
    |> String.trim_leading(prefix)
    |> String.trim_trailing(suffix)
    |> String.replace("\n      ", "\n")
  end

  @spec pretty_print_type(type :: String.t()) :: String.t()
  def pretty_print_type(type) do
    prefix = "@spec a("
    suffix = ") :: :ok\ndef a() do\n  :ok\nend"
    indented_suffix = ") ::\n        :ok\ndef a() do\n  :ok\nend"
    pretty = pretty_print(type)

    """
    @spec a(#{pretty}) :: :ok
    def a() do
      :ok
    end
    """
    |> format()
    |> Enum.join("")
    |> String.trim_leading(prefix)
    |> String.trim_trailing(suffix)
    |> String.trim_trailing(indented_suffix)
    |> String.replace("\n      ", "\n")
  end

  @spec pretty_print_args(args :: String.t()) :: String.t()
  def pretty_print_args(args) do
    prefix = "@spec a"
    suffix = " :: :ok\ndef a() do\n  :ok\nend"
    pretty = pretty_print(args)

    """
    @spec a#{pretty} :: :ok
    def a() do
      :ok
    end
    """
    |> format()
    |> Enum.join("")
    |> String.trim_leading(prefix)
    |> String.trim_trailing(suffix)
    |> String.replace("\n      ", "\n")
  end

  defp do_pretty_print({:any}) do
    "_"
  end

  defp do_pretty_print({:inner_any_function}) do
    "(...)"
  end

  defp do_pretty_print({:any_function}) do
    "(... -> any)"
  end

  defp do_pretty_print({:assignment, {:atom, atom}, value}) do
    "#{normalize_name(atom)} = #{do_pretty_print(value)}"
  end

  defp do_pretty_print({:atom, [:_]}) do
    "_"
  end

  defp do_pretty_print({:atom, ['_']}) do
    "_"
  end

  defp do_pretty_print({:atom, atom}) do
    atomize(atom)
  end

  defp do_pretty_print({:binary_part, value, _, size}) do
    "#{do_pretty_print(value)} :: #{do_pretty_print(size)}"
  end

  defp do_pretty_print({:binary_part, value, size}) do
    "#{do_pretty_print(value)} :: #{do_pretty_print(size)}"
  end

  defp do_pretty_print({:binary, [{:binary_part, {:any}, {:any}, {:size, {:int, 8}}}]}) do
    "binary()"
  end

  defp do_pretty_print({:binary, [{:binary_part, {:any}, {:any}, {:size, {:int, 1}}}]}) do
    "bitstring()"
  end

  defp do_pretty_print({:binary, binary_parts}) do
    binary_parts = Enum.map_join(binary_parts, ", ", &do_pretty_print/1)
    "<<#{binary_parts}>>"
  end

  defp do_pretty_print({:binary, value, size}) do
    "<<#{do_pretty_print(value)} :: #{do_pretty_print(size)}>>"
  end

  defp do_pretty_print({:byte_list, byte_list}) do
    byte_list
    |> Enum.into(<<>>, fn byte ->
      <<byte::8>>
    end)
    |> inspect()
  end

  defp do_pretty_print({:contract, {:args, args}, {:return, return}, {:whens, whens}}) do
    {printed_whens, when_names} = collect_and_print_whens(whens)

    args = {:when_names, when_names, args}
    return = {:when_names, when_names, return}

    "(#{do_pretty_print(args)}) :: #{do_pretty_print(return)} when #{printed_whens}"
  end

  defp do_pretty_print({:contract, {:args, {:inner_any_function}}, {:return, return}}) do
    "((...) -> #{do_pretty_print(return)})"
  end

  defp do_pretty_print({:contract, {:args, args}, {:return, return}}) do
    "#{do_pretty_print(args)} :: #{do_pretty_print(return)}"
  end

  defp do_pretty_print({:function, {:contract, {:args, args}, {:return, return}}}) do
    "(#{do_pretty_print(args)} -> #{do_pretty_print(return)})"
  end

  defp do_pretty_print({:int, int}) do
    "#{to_string(int)}"
  end

  defp do_pretty_print({:list, :paren, items}) do
    "(#{Enum.map_join(items, ", ", &do_pretty_print/1)})"
  end

  defp do_pretty_print(
         {:list, :square,
          [
            tuple: [
              {:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}},
              {:atom, [:_]}
            ]
          ]}
       ) do
    "Keyword.t()"
  end

  defp do_pretty_print(
         {:list, :square,
          [
            tuple: [
              {:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}},
              t
            ]
          ]}
       ) do
    "Keyword.t(#{do_pretty_print(t)})"
  end

  defp do_pretty_print({:list, :square, items}) do
    "[#{Enum.map_join(items, ", ", &do_pretty_print/1)}]"
  end

  defp do_pretty_print({:map_entry, key, value}) do
    "#{do_pretty_print(key)} => #{do_pretty_print(value)}"
  end

  defp do_pretty_print(
         {:map,
          [
            {:map_entry, {:atom, '\'__struct__\''}, {:atom, [:_]}},
            {:map_entry, {:atom, [:_]}, {:atom, [:_]}}
          ]}
       ) do
    "struct()"
  end

  defp do_pretty_print(
         {:map,
          [
            {:map_entry, {:atom, '\'__struct__\''},
             {:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}}},
            {:map_entry, {:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}}, {:atom, [:_]}}
          ]}
       ) do
    "struct()"
  end

  defp do_pretty_print(
         {:map,
          [
            {:map_entry, {:atom, '\'__struct__\''},
             {:type_list, ['a', 't', 'o', 'm'], {:list, :paren, []}}},
            {:map_entry, {:atom, [:_]}, {:atom, [:_]}}
          ]}
       ) do
    "struct()"
  end

  defp do_pretty_print(
         {:map,
          [
            {:map_entry, {:atom, '\'__exception__\''}, {:atom, '\'true\''}},
            {:map_entry, {:atom, '\'__struct__\''}, {:atom, [:_]}},
            {:map_entry, {:atom, [:_]}, {:atom, [:_]}}
          ]}
       ) do
    "Exception.t()"
  end

  defp do_pretty_print({:map, map_keys}) do
    case struct_parts(map_keys) do
      %{name: name, entries: [{:map_entry, {:atom, [:_]}, {:atom, [:_]}}]} ->
        "%#{name}{}"

      %{name: name, entries: entries} ->
        "%#{name}{#{Enum.map_join(entries, ", ", &do_pretty_print/1)}}"
    end
  end

  defp do_pretty_print({:named_type_with_appended_colon, named_type, type})
       when is_tuple(named_type) and is_tuple(type) do
    case named_type do
      {:atom, name} ->
        "#{normalize_name(name)}: #{do_pretty_print(type)}"

      other ->
        "#{do_pretty_print(other)}: #{do_pretty_print(type)}"
    end
  end

  defp do_pretty_print({:named_type, named_type, type})
       when is_tuple(named_type) and is_tuple(type) do
    case named_type do
      {:atom, name} ->
        "#{normalize_name(name)} :: #{do_pretty_print(type)}"

      other ->
        "#{do_pretty_print(other)} :: #{do_pretty_print(type)}"
    end
  end

  defp do_pretty_print({:named_type, named_type, type}) when is_tuple(named_type) do
    case named_type do
      {:atom, name = '\'Elixir' ++ _} ->
        "#{atomize(name)}.#{deatomize(type)}()"

      {:atom, name} ->
        "#{normalize_name(name)} :: #{deatomize(type)}()"

      other ->
        name = do_pretty_print(other)
        "#{name} :: #{deatomize(type)}()"
    end
  end

  defp do_pretty_print({nil}) do
    "nil"
  end

  defp do_pretty_print({:pattern, pattern_items}) do
    "#{Enum.map_join(pattern_items, ", ", &do_pretty_print/1)}"
  end

  defp do_pretty_print(
         {:pipe_list, {:atom, ['f', 'a', 'l', 's', 'e']}, {:atom, ['t', 'r', 'u', 'e']}}
       ) do
    "boolean()"
  end

  defp do_pretty_print(
         {:pipe_list, {:atom, '\'infinity\''},
          {:type_list, ['n', 'o', 'n', :_, 'n', 'e', 'g', :_, 'i', 'n', 't', 'e', 'g', 'e', 'r'],
           {:list, :paren, []}}}
       ) do
    "timeout()"
  end

  defp do_pretty_print({:pipe_list, head, tail}) do
    "#{do_pretty_print(head)} | #{do_pretty_print(tail)}"
  end

  defp do_pretty_print({:range, from, to}) do
    "#{do_pretty_print(from)}..#{do_pretty_print(to)}"
  end

  defp do_pretty_print({:rest}) do
    "..."
  end

  defp do_pretty_print({:size, size}) do
    "size(#{do_pretty_print(size)})"
  end

  defp do_pretty_print({:tuple, tuple_items}) do
    "{#{Enum.map_join(tuple_items, ", ", &do_pretty_print/1)}}"
  end

  defp do_pretty_print({:type, type}) do
    "#{deatomize(type)}()"
  end

  defp do_pretty_print({:type, module, type}) do
    module = do_pretty_print(module)

    type =
      if is_tuple(type) do
        do_pretty_print(type)
      else
        deatomize(type) <> "()"
      end

    "#{module}.#{type}"
  end

  defp do_pretty_print({:type, module, type, inner_type}) do
    "#{atomize(module)}.#{deatomize(type)}(#{do_pretty_print(inner_type)})"
  end

  defp do_pretty_print({:type_list, type, types}) do
    "#{deatomize(type)}#{do_pretty_print(types)}"
  end

  defp do_pretty_print({:when_names, when_names, {:list, :paren, items}}) do
    Enum.map_join(items, ", ", &format_when_names(do_pretty_print(&1), when_names))
  end

  defp do_pretty_print({:when_names, when_names, item}) do
    format_when_names(do_pretty_print(item), when_names)
  end

  defp format_when_names(item, when_names) do
    trimmed = String.trim_leading(item, ":")

    if trimmed in when_names do
      downcase_first(trimmed)
    else
      item
    end
  end

  defp collect_and_print_whens(whens) do
    {pretty_names, when_names} =
      Enum.reduce(whens, {[], []}, fn {_, when_name, type}, {prettys, whens} ->
        pretty_name =
          {:named_type_with_appended_colon, when_name, type}
          |> do_pretty_print()
          |> downcase_first()

        {[pretty_name | prettys], [when_name | whens]}
      end)

    when_names =
      Enum.map(when_names, fn {_, name} ->
        name
        |> atomize()
        |> String.trim_leading(":")
      end)

    printed_whens =
      pretty_names
      |> Enum.reverse()
      |> Enum.join(", ")

    {printed_whens, when_names}
  end

  defp downcase_first(string) do
    {first, rest} = String.split_at(string, 1)
    String.downcase(first) <> rest
  end

  defp atomize("Elixir." <> module_name) do
    String.trim(module_name, "'")
  end

  defp atomize([char]) do
    to_string(char)
  end

  defp atomize(atom) when is_list(atom) do
    atom_string =
      atom
      |> deatomize()
      |> to_string()

    stripped = strip_var_version(atom_string)

    if stripped == atom_string do
      atomize(stripped)
    else
      stripped
    end
  end

  defp atomize(<<number>>) when is_number(number) do
    to_string(number)
  end

  defp atomize(atom) do
    atom = to_string(atom)

    if String.starts_with?(atom, "_") do
      atom
    else
      atom
      |> String.trim("'")
      |> String.to_atom()
      |> inspect()
    end
  end

  defp atom_part_to_string({:int, atom_part}), do: Integer.to_charlist(atom_part)
  defp atom_part_to_string(atom_part), do: atom_part

  defp strip_var_version(var_name) do
    var_name
    |> String.replace(~r/^V(.+)@\d+$/, "\\1")
    |> String.replace(~r/^(.+)@\d+$/, "\\1")
  end

  defp struct_parts(map_keys) do
    %{name: name, entries: entries} =
      Enum.reduce(map_keys, %{name: "", entries: []}, &struct_part/2)

    %{name: name, entries: Enum.reverse(entries)}
  end

  defp struct_part({:map_entry, {:atom, '\'__struct__\''}, {:atom, name}}, struct_parts) do
    name =
      name
      |> atomize()
      |> String.trim("\"")

    Map.put(struct_parts, :name, name)
  end

  defp struct_part(entry, struct_parts = %{entries: entries}) do
    Map.put(struct_parts, :entries, [entry | entries])
  end

  defp deatomize([:_, :_, '@', {:int, _}]) do
    "_"
  end

  defp deatomize(chars) when is_list(chars) do
    Enum.map(chars, fn char ->
      char
      |> deatomize_char()
      |> atom_part_to_string()
    end)
  end

  defp deatomize_char(char) when is_atom(char) do
    Atom.to_string(char)
  end

  defp deatomize_char(char), do: char

  defp normalize_name(name) do
    name
    |> deatomize()
    |> to_string()
    |> strip_var_version()
  end
end
