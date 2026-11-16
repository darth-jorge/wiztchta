defmodule Wiztchta.AdaptiveTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Wiztchta.Adaptive
  alias Wiztchta.Challenges.{Math, ProofOfWork}

  defp unique_client, do: "client-" <> Integer.to_string(System.unique_integer([:positive]))

  defp difficulties(n, opts) do
    for _ <- 1..n, do: Wiztchta.new([type: ProofOfWork] ++ opts).public["difficulty"]
  end

  describe "pressure_for/2" do
    test "matches the documented table" do
      expected = %{1 => 0, 5 => 0, 6 => 1, 10 => 1, 11 => 2, 20 => 2, 21 => 3, 40 => 3, 41 => 4}

      for {count, bits} <- expected do
        assert Adaptive.pressure_for(count, 5) == bits, "count #{count}"
      end
    end
  end

  describe "Wiztchta.new/1" do
    test "raises difficulty as a visitor asks for more challenges, up to the cap" do
      client = unique_client()
      # 100 > 80, where the formula alone would pass the default cap of 20.
      levels = difficulties(100, client: client)

      assert Enum.slice(levels, 0..4) |> Enum.uniq() == [16]
      assert Enum.at(levels, 5) == 17
      assert Enum.at(levels, 10) == 18
      assert Enum.at(levels, 20) == 19
      assert Enum.at(levels, 40) == 20
      assert Enum.at(levels, 99) == 20
      assert Enum.max(levels) == 20
    end

    test "visitors are counted separately" do
      difficulties(10, client: unique_client())
      assert difficulties(1, client: unique_client()) == [16]
    end

    test "adds pressure on top of a per-form difficulty, within the cap" do
      client = unique_client()
      levels = difficulties(12, client: client, difficulty: 18)
      assert hd(levels) == 18
      assert List.last(levels) == 20
    end

    test "a per-form difficulty above the cap is kept, never lowered" do
      assert difficulties(1, client: unique_client(), difficulty: 22) == [22]
    end

    test "honours a custom cap and free allowance" do
      levels = difficulties(4, client: unique_client(), rate_free: 1, pow_max_difficulty: 17)
      assert levels == [16, 17, 17, 17]
    end

    test "nothing changes without a client key, with client: false, or without a limiter" do
      assert difficulties(10, []) |> Enum.uniq() == [16]
      assert difficulties(10, client: false) |> Enum.uniq() == [16]
      assert difficulties(10, client: unique_client(), rate_limiter: nil) |> Enum.uniq() == [16]
    end

    test "challenge types that don't use pressure ignore it" do
      client = unique_client()

      for _ <- 1..20,
          do: assert(%Wiztchta.Challenge{type: Math} = Wiztchta.new(type: Math, client: client))
    end

    test "the ClientKey plug makes it automatic for the request" do
      levels =
        Task.async(fn ->
          # A unique IPv6 /64 per run, so parallel tests never share a counter.
          n = System.unique_integer([:positive])
          ip = {0x2001, 0xDB8, div(n, 0x10000) |> rem(0x10000), rem(n, 0x10000), 0, 0, 0, 1}
          %{conn(:get, "/") | remote_ip: ip} |> Wiztchta.ClientKey.call([])
          difficulties(6, [])
        end)
        |> Task.await()

      assert List.last(levels) == 17
    end
  end

  describe "invalid configuration" do
    test "rejects zero or invalid rate settings instead of hanging" do
      for {key, bad} <- [rate_free: 0, rate_window: 0, rate_free: -1, rate_window: "600"] do
        assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
          Wiztchta.new([{key, bad}, client: unique_client()])
        end
      end
    end

    test "rejects invalid client keys and caps" do
      assert_raise ArgumentError, ~r/:client must be/, fn -> Wiztchta.new(client: 123) end

      assert_raise ArgumentError, ~r/from 1 to 32/, fn ->
        Wiztchta.new(client: unique_client(), pow_max_difficulty: 40)
      end
    end
  end
end
