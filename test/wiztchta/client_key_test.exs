defmodule Wiztchta.ClientKeyTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Wiztchta.ClientKey

  test "the same IPv4 address always maps to the same key, others differ" do
    assert ClientKey.for({203, 0, 113, 7}) == ClientKey.for({203, 0, 113, 7})
    refute ClientKey.for({203, 0, 113, 7}) == ClientKey.for({203, 0, 113, 8})
  end

  test "keys don't contain the raw address and depend on the secret" do
    key = ClientKey.for({203, 0, 113, 7})
    refute key =~ "203"
    refute key == ClientKey.for({203, 0, 113, 7}, secret_key_base: String.duplicate("x", 64))
  end

  test "IPv6 addresses are grouped by /64" do
    a = ClientKey.for({0x2001, 0xDB8, 0x1, 0x2, 0, 0, 0, 1})
    same_64 = ClientKey.for({0x2001, 0xDB8, 0x1, 0x2, 0xFFFF, 0xABCD, 0x1234, 0x5678})
    other_64 = ClientKey.for({0x2001, 0xDB8, 0x1, 0x3, 0, 0, 0, 1})

    assert a == same_64
    refute a == other_64
  end

  test "IPv4-mapped IPv6 is the same visitor as plain IPv4" do
    assert ClientKey.for({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}) ==
             ClientKey.for({203, 0, 113, 7})
  end

  test "for/1 reads a conn's remote_ip" do
    conn = %{conn(:get, "/") | remote_ip: {198, 51, 100, 1}}
    assert ClientKey.for(conn) == ClientKey.for({198, 51, 100, 1})
  end

  test "for/1 reads a LiveView socket's peer data" do
    connected = %Phoenix.LiveView.Socket{
      private: %{connect_info: %{peer_data: %{address: {198, 51, 100, 2}}}}
    }

    without_peer_data = %Phoenix.LiveView.Socket{private: %{connect_info: %{}}}

    assert ClientKey.for(connected) == ClientKey.for({198, 51, 100, 2})
    assert ClientKey.for(without_peer_data) == nil
    assert ClientKey.for(nil) == nil
  end

  test "the plug records the key for the current request process only" do
    key =
      Task.async(fn ->
        %{conn(:get, "/") | remote_ip: {198, 51, 100, 3}} |> ClientKey.call(ClientKey.init([]))
        ClientKey.current()
      end)
      |> Task.await()

    assert key == ClientKey.for({198, 51, 100, 3})
    assert ClientKey.current() == nil
  end
end
