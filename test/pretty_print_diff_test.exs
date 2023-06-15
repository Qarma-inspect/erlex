defmodule Erlex.Test.PretyPrintDiffTest do
  use ExUnit.Case

  # test "binary" do
  #   expected = 'binary()'

  #   actual = '<<_:48>>'

  #   pretty_printed = Erlex.pretty_print_diff(expected, actual)

  #   expected_output = ~S"""
  #   Found mismatched fields: []
  #   """

  #   assert pretty_printed == expected_output
  # end

  test "struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.Complex\', \'first\':=binary(), \'second\':=binary(), \'third\':={atom(),binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.Complex\', \'first\':=\'nil\', \'second\':=<<_:48>>, \'third\':={\'ok\',<<_:56>>}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""
    Found mismatched fields: [[:first]]
    """

    assert pretty_printed == expected_output
  end

  test "nested struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=binary(), \'second\':=\#{\'a\':=binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=float(), \'second\':=\#{\'a\':=float()}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""
    Found mismatched fields: [[:first], [:second, :a]]
    """

    assert pretty_printed == expected_output
  end

  test "nested struct with unexpected fields" do
    expected =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=\#{\'a\':=binary(), \'b\':=non_neg_integer()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=\#{\'a\':=float(), \'c\':=<<_:64>>}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""
    Found mismatched fields: [[:first, :a], [:first, :b], [:first, :c]]
    """

    assert pretty_printed == expected_output
  end

  test "different nested struct" do
    expected =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=\#{\'__struct__\':=\'StructA\', \'a\':=binary()}}'

    actual =
      '\#{\'__struct__\':=\'Elixir.DialyzerFun.NestedStruct.Type\', \'first\':=\#{\'__struct__\':=\'StructB\', \'a\':=float()}}'

    pretty_printed = Erlex.pretty_print_diff(expected, actual)

    expected_output = ~S"""
    Found mismatched fields: [[:first]]
    """

    assert pretty_printed == expected_output
  end
end
