defmodule Rbtz.CoverModuleTest do
  use ExUnit.Case, async: true

  test "module is loaded and exposes the Mix test_coverage entry point" do
    assert Code.ensure_loaded?(Rbtz.CoverModule)
    assert function_exported?(Rbtz.CoverModule, :start, 2)
  end

  test "with_silenced_io/1 swaps the group leader for the callback and restores it after" do
    original_group_leader = Process.group_leader()

    captured =
      Rbtz.CoverModule.with_silenced_io(fn ->
        IO.write("this should not appear")
        Process.group_leader()
      end)

    refute captured == original_group_leader
    assert Process.group_leader() == original_group_leader
  end
end
