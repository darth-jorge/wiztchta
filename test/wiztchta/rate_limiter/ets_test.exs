defmodule Wiztchta.RateLimiter.ETSTest do
  use ExUnit.Case, async: true

  alias Wiztchta.RateLimiter.ETS

  defp unique_key, do: "rl-" <> Integer.to_string(System.unique_integer([:positive]))

  test "counts hits per key within a window" do
    key = unique_key()
    assert ETS.hit(key, 600, now: 1_000) == 1
    assert ETS.hit(key, 600, now: 1_001) == 2
    assert ETS.hit(unique_key(), 600, now: 1_001) == 1
  end

  test "a new window starts from zero" do
    key = unique_key()
    assert ETS.hit(key, 600, now: 599) == 1
    assert ETS.hit(key, 600, now: 599) == 2
    assert ETS.hit(key, 600, now: 600) == 1
  end

  test "sweep/1 removes finished windows only" do
    old = unique_key()
    current = unique_key()
    ETS.hit(old, 60, now: 100)
    ETS.hit(current, 60, now: 170)

    ETS.sweep(170)

    assert ETS.hit(old, 60, now: 100) == 1
    assert ETS.hit(current, 60, now: 170) == 2
  end
end
