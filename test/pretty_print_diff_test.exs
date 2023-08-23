defmodule Erlex.Test.PretyPrintDiffTest do
  use ExUnit.Case

  test "binary" do
    expected = 'binary()'
    actual = '3'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    assert pretty_printed == ""
  end

  test "union type" do
    expected = 'binary() | non_neg_integer()'
    actual = '\'ok\''

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    assert pretty_printed == ""
  end

  test "struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=binary(), \'second\':=binary(), \'third\':={atom(),binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=\'nil\', \'second\':=<<_:48>>, \'third\':={\'ok\',<<_:56>>}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first]: expected "binary()", got "nil"
    """

    assert pretty_printed == expected_output
  end

  test "nested struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=binary(), \'second\':=\#{\'a\':=binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=float(), \'second\':=\#{\'a\':=\#{\'b\':=binary()}}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first]: expected "binary()", got "float()"
    [:second, :a]: expected "binary()", got "%{}"
    """

    assert pretty_printed == expected_output
  end

  test "nested struct with unexpected fields" do
    expected =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=\#{\'a\':=binary(), \'b\':=non_neg_integer()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=\#{\'a\':=float(), \'c\':=<<_:64>>}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first, :a]: expected "binary()", got "float()"
    [:first, :b]: not found
    [:first, :c]: unexpected key
    """

    assert pretty_printed == expected_output
  end

  test "different nested struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=\#{\'__struct__\':=\'StructA\', \'a\':=binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.SomeStruct\', \'first\':=\#{\'__struct__\':=\'StructB\', \'a\':=float()}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first]: expected "StructA", got "StructB"
    """

    assert pretty_printed == expected_output
  end

  test "nil in a map" do
    expected = '\#{\'a\':=\'nil\', \'b\':=binary()}'

    actual = '\#{\'a\':=\'nil\', \'b\':=float()}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:b]: expected "binary()", got "float()"
    """

    assert pretty_printed == expected_output
  end

  test "union type in a map" do
    expected = '\#{\'a\':=binary() | non_neg_integer()}'

    actual = '\#{\'a\':=\'ok\'}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:a]: expected "binary() | non_neg_integer()", got ":ok"
    """

    assert pretty_printed == expected_output
  end

  test "tuple" do
    expected =
      '{binary(),non_neg_integer(),atom(), float()}'

    actual =
      '{float(),<<_:24>>,\'ok\',float()}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [0]: expected "binary()", got "float()"
    [1]: expected "non_neg_integer()", got "<<_ :: 24>>"
    """

    assert pretty_printed == expected_output
  end

  test "nested map and tuple" do
    expected =
      '\#{\'first\':=binary(),\'second\':={float(),\#{\'a\':=atom(),\'b\':={binary(),binary()}}}}'

    actual =
      '\#{\'first\':=float(),\'second\':={<<_:24>>,\#{\'a\':=\'ok\',\'b\':={binary(),\'ok\'}}}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first]: expected "binary()", got "float()"
    [:second, 0]: expected "float()", got "<<_ :: 24>>"
    [:second, 1, :b, 1]: expected "binary()", got ":ok"
    """

    assert pretty_printed == expected_output
  end

  test "different tuple size" do
    expected = '{binary(),non_neg_integer(),binary()}'

    actual = '{binary(),<<_:24>>}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Expected tuple size is 3, got one of size 2.
    """

    assert pretty_printed == expected_output
  end

  test "different nested tuple size" do
    expected = '\#{\'first\':={float(),float(),float()}, \'second\':={float(),binary()}}'

    actual = '\#{\'first\':={float(),binary()}, \'second\':={float(),float(),float()}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    Mismatched fields:
    [:first]: expected tuple size is 3, got one of size 2
    [:second]: expected tuple size is 2, got one of size 3
    """

    assert pretty_printed == expected_output
  end

  test "different function arguments" do
    expected = '(\#{\'a\':=\'ok\', \'b\':=\'error\', _=>_},binary())'

    actual = '(\#{\'a\'=>\'ok\', \'c\'=>\'error\'},float())'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""

    1st argument:
    [:b]: not found
    [:c]: unexpected key
    """

    assert pretty_printed == expected_output
  end

  test "broken contract" do
    expected_contract = '(\#{\'a\':=\'ok\',\'b\':=\'error\'},\'ok\') -> \'ok\''

    actual_args = '(\#{\'a\'=>\'ok\',\'b\':=\'ok\'},\'ok\')'

    pretty_printed = Erlex.pretty_print_diff(expected_contract, actual_args)

    expected_output = ~S"""

    1st argument:
    [:b]: expected ":error", got ":ok"
    """

    assert pretty_printed == expected_output
  end
end
