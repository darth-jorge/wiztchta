defmodule Wiztchta.BindingTest do
  # Runs the real Plug.CSRFProtection, because session binding relies on the
  # state it loads into the request process. If Plug changes how it stores
  # that state, these tests fail instead of binding silently turning off.
  use ExUnit.Case, async: true

  import Plug.Test
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Wiztchta.Test.FixedChallenge

  @secret_key_base String.duplicate("binding-test-secret-", 4)

  # Every request runs in its own process, like in production.
  defp request(fun), do: fn -> fun.() end |> Task.async() |> Task.await()

  # Builds a conn that went through protect_from_forgery with `session`.
  defp csrf_conn(method, session, params \\ %{}) do
    conn(method, "/form", params)
    |> Map.put(:secret_key_base, @secret_key_base)
    |> init_test_session(session)
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))
  end

  # GET request that renders <.wiztchta>; returns the token and the session
  # CSRF state Plug would save in the cookie.
  defp render_form(session \\ %{}, opts \\ []) do
    request(fn ->
      csrf_conn(:get, session)

      html =
        render_component(&Wiztchta.Components.wiztchta/1,
          type: FixedChallenge,
          opts: opts
        )

      [_, token] = Regex.run(~r/name="wiztchta\[token\]" value="([^"]+)"/, html)
      {token, Plug.CSRFProtection.dump_state()}
    end)
  end

  # POST request through Wiztchta.Plug in the session holding `state`.
  defp submit(token, state, plug_opts \\ []) do
    request(fn ->
      params = %{"wiztchta" => %{"token" => token, "response" => "42"}}

      csrf_conn(:post, %{"_csrf_token" => state}, params)
      |> Wiztchta.Plug.call(Wiztchta.Plug.init(plug_opts))
      |> Map.fetch!(:assigns)
      |> Map.fetch!(:wiztchta)
    end)
  end

  describe "controllers (automatic)" do
    test "a form submitted in the session that rendered it verifies" do
      {token, state} = render_form()
      assert submit(token, state) == :ok
    end

    test "a token from another session is rejected" do
      {token, _state} = render_form()
      {_other_token, other_state} = render_form()

      assert submit(token, other_state) == {:error, :session_mismatch}
    end

    test "a mismatch does not consume the token" do
      {token, state} = render_form()
      {_other_token, other_state} = render_form()

      assert submit(token, other_state) == {:error, :session_mismatch}
      assert submit(token, state) == :ok
    end

    test "Wiztchta.new/1 and verify/2 called by hand in controllers bind too" do
      {challenge, state} =
        request(fn ->
          csrf_conn(:get, %{})
          {Wiztchta.new(type: FixedChallenge), Plug.CSRFProtection.dump_state()}
        end)

      result =
        request(fn ->
          csrf_conn(:post, %{"_csrf_token" => state})
          Wiztchta.verify(%{"token" => challenge.token, "response" => "42"})
        end)

      assert result == :ok
    end

    test "bind: false opts out, and must be used on both sides" do
      {token, state} = render_form(%{}, bind: false)
      {_other_token, other_state} = render_form()

      assert submit(token, other_state, bind: false) == :ok
      {token, _state} = render_form(%{}, bind: false)
      assert submit(token, state) == {:error, :session_mismatch}
    end
  end

  describe "without protect_from_forgery" do
    test "nothing is bound, so forms keep working" do
      result =
        request(fn ->
          html = render_component(&Wiztchta.Components.wiztchta/1, type: FixedChallenge)
          [_, token] = Regex.run(~r/name="wiztchta\[token\]" value="([^"]+)"/, html)
          Wiztchta.verify(%{"token" => token, "response" => "42"})
        end)

      assert result == :ok
      assert request(&Wiztchta.Binding.current/0) == nil
    end
  end

  describe "LiveView (opt-in)" do
    test "session_binding/1 matches the binding controllers compute" do
      {_token, state} = render_form()

      from_request =
        request(fn -> csrf_conn(:get, %{"_csrf_token" => state}) && Wiztchta.Binding.current() end)

      assert Wiztchta.session_binding(%{"_csrf_token" => state}) == from_request
      refute from_request == nil
    end

    test "binding a challenge to the LiveView session" do
      {_token, state} = render_form()
      {_other, other_state} = render_form()
      binding = Wiztchta.session_binding(%{"_csrf_token" => state})
      challenge = Wiztchta.new(type: FixedChallenge, bind: binding)
      params = %{"token" => challenge.token, "response" => "42"}

      assert {:error, :session_mismatch} =
               Wiztchta.verify(params,
                 bind: Wiztchta.session_binding(%{"_csrf_token" => other_state})
               )

      assert :ok = Wiztchta.verify(params, bind: binding)
    end

    test "an unbound LiveView token is rejected by a controller that binds" do
      {_token, state} = render_form()
      challenge = Wiztchta.new(type: FixedChallenge)
      assert submit(challenge.token, state) == {:error, :session_mismatch}
    end

    test "session_binding/1 returns nil without CSRF state" do
      assert Wiztchta.session_binding(%{}) == nil
      assert Wiztchta.session_binding(%{"_csrf_token" => "too-short"}) == nil
    end
  end

  test "tokens issued before binding existed count as unbound" do
    legacy = %{
      id: "legacy-bind-" <> Integer.to_string(System.unique_integer([:positive])),
      type: FixedChallenge,
      secret: "42",
      expires_at: System.system_time(:second) + 300
    }

    token = Wiztchta.Token.encrypt(legacy, 300, [])
    {_token, state} = render_form()

    assert submit(token, state) == {:error, :session_mismatch}
    assert submit(token, state, bind: false) == :ok
  end

  test ":bind rejects invalid values" do
    for bad <- ["", true, 123, %{}] do
      assert_raise ArgumentError, ~r/:bind must be/, fn ->
        Wiztchta.new(type: FixedChallenge, bind: bad)
      end
    end
  end
end
