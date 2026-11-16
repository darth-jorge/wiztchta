defmodule Wiztchta.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Test

  defp call(params, opts \\ []) do
    conn(:post, "/contact", params) |> Wiztchta.Plug.call(Wiztchta.Plug.init(opts))
  end

  test "assigns :ok for a valid submission without halting" do
    challenge = Wiztchta.new(type: Wiztchta.Test.FixedChallenge)
    conn = call(%{"wiztchta" => %{"token" => challenge.token, "response" => "42"}})

    assert conn.assigns.wiztchta == :ok
    refute conn.halted
  end

  test "forwards the scope option to verify" do
    challenge = Wiztchta.new(type: Wiztchta.Test.FixedChallenge, scope: "signup")
    params = %{"wiztchta" => %{"token" => challenge.token, "response" => "42"}}

    assert call(params, scope: "contact").assigns.wiztchta == {:error, :scope_mismatch}
    assert call(params, scope: "signup").assigns.wiztchta == :ok
  end

  test "assigns the error for an invalid submission" do
    conn = call(%{"name" => "bot"})

    assert conn.assigns.wiztchta == {:error, :missing}
    refute conn.halted
  end
end
