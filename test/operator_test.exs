defmodule OperatorTest do
  use ExUnit.Case

  test "returns version" do
    assert Operator.version() == "0.1.0"
  end
end
