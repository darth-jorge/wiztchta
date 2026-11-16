defmodule Wiztchta.Binding do
  @moduledoc """
  Session binding: ties a challenge to the visitor's browser session, so a
  token solved in one session can't be submitted from another.

  The session is identified by the per-session secret that
  `Plug.CSRFProtection` (`protect_from_forgery`) already keeps in every
  Phoenix session. Only a hash of it is ever stored in a challenge.

  ## Defaults

  Binding is automatic wherever CSRF protection is active in the current
  request process: controller actions and the templates they render (the
  standard `:browser` pipeline). Both `Wiztchta.new/1` and
  `Wiztchta.verify/2` (and so `Wiztchta.Plug`) bind in that case.

  LiveView processes have no request, so challenges created there are
  unbound unless you opt in with `Wiztchta.session_binding/1`:

      binding = Wiztchta.session_binding(session)       # in mount/3
      Wiztchta.new(bind: binding)
      Wiztchta.verify(params, bind: binding)

  Pass `bind: false` to `new/1`, `verify/2` or `Wiztchta.Plug` to opt out.
  """

  @prefix "wiztchta-session:"

  @doc """
  The binding for the current request process, or `nil` when
  `Plug.CSRFProtection` hasn't run in it (e.g. in a LiveView process or a
  pipeline without `protect_from_forgery`).
  """
  @spec current() :: String.t() | nil
  def current do
    # protect_from_forgery calls Plug.CSRFProtection.load_state/2, which sets
    # this key. It is Plug-internal; test/wiztchta/binding_test.exs runs the
    # real plug, so a change in Plug fails the suite instead of silently
    # disabling binding.
    if is_map(Process.get(:plug_csrf_token_per_host)) do
      hash(Plug.CSRFProtection.dump_state())
    end
  end

  @doc """
  The binding for a session map (as given to LiveView's `mount/3`), or `nil`
  if it has no CSRF state.
  """
  @spec from_session(map) :: String.t() | nil
  def from_session(session) when is_map(session) do
    case Plug.CSRFProtection.dump_state_from_session(session["_csrf_token"]) do
      nil -> nil
      state -> hash(state)
    end
  end

  @doc false
  # Resolves the :bind option. A missing option means "automatic".
  def resolve!(opts) do
    case Keyword.fetch(opts, :bind) do
      :error ->
        current()

      {:ok, nil} ->
        nil

      {:ok, false} ->
        nil

      {:ok, binding} when is_binary(binding) and binding != "" ->
        binding

      {:ok, other} ->
        raise ArgumentError, ":bind must be a string, nil or false, got: #{inspect(other)}"
    end
  end

  @doc false
  def match?(nil, nil), do: true
  def match?(a, b) when is_binary(a) and is_binary(b), do: Plug.Crypto.secure_compare(a, b)
  def match?(_, _), do: false

  defp hash(state) do
    Base.url_encode64(:crypto.hash(:sha256, @prefix <> state), padding: false)
  end
end
