defmodule Wiztchta.ClientKey do
  @moduledoc """
  Identifies a visitor for adaptive difficulty, by IP address.

  * IPv4 addresses are used as-is; IPv6 addresses are grouped by their /64
    prefix, since one connection usually owns a whole /64 and a bot could
    rotate addresses inside it.
  * Keys are an HMAC of the address with your secret, so raw IPs are never
    stored and can't be recovered (a plain hash of an IPv4 address could be
    reversed by hashing all 2^32 of them).

  ## Controllers

  Add the plug to your `:browser` pipeline; challenges created while
  rendering that request pick up the key automatically:

      plug Wiztchta.ClientKey

  ## LiveView

      Wiztchta.new(client: Wiztchta.client_key(socket))   # in mount/3

  This reads the peer address, which needs `connect_info: [:peer_data]` on
  your LiveView socket in the endpoint.

  ## Behind a proxy

  Behind a load balancer or CDN, the peer address is the proxy's, so every
  visitor would share one key. Set the real client IP first, e.g. with the
  `remote_ip` library before this plug, and in LiveView compute the IP from
  `connect_info: [:x_headers]` and pass it: `Wiztchta.client_key(ip)`. Never
  trust `X-Forwarded-For` blindly; clients can forge it.
  """

  @behaviour Plug

  @process_key :wiztchta_client_key

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    Process.put(@process_key, from_ip(conn.remote_ip, opts))
    conn
  end

  @doc "The key recorded by the plug for the current request, if any."
  @spec current() :: String.t() | nil
  def current, do: Process.get(@process_key)

  @doc """
  The key for a `Plug.Conn`, a LiveView socket or an IP address tuple.
  Returns `nil` when the address is unknown.
  """
  @spec for(Plug.Conn.t() | Phoenix.LiveView.Socket.t() | :inet.ip_address() | nil, keyword) ::
          String.t() | nil
  def for(source, opts \\ [])

  def for(%Plug.Conn{remote_ip: ip}, opts), do: from_ip(ip, opts)

  def for(%Phoenix.LiveView.Socket{} = socket, opts) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: ip} -> from_ip(ip, opts)
      _ -> nil
    end
  end

  def for(ip, opts) when is_tuple(ip), do: from_ip(ip, opts)
  def for(nil, _opts), do: nil

  @doc false
  def from_ip(ip, opts \\ [])

  # IPv4-mapped IPv6 (::ffff:a.b.c.d) is the same visitor as a.b.c.d.
  def from_ip({0, 0, 0, 0, 0, 0xFFFF, hi, lo}, opts) do
    from_ip({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)}, opts)
  end

  def from_ip({_, _, _, _} = ipv4, opts), do: digest("v4:" <> to_string(:inet.ntoa(ipv4)), opts)

  def from_ip({a, b, c, d, _, _, _, _}, opts) do
    prefix = Enum.map_join([a, b, c, d], ":", &Integer.to_string(&1, 16))
    digest("v6/64:" <> prefix, opts)
  end

  def from_ip(_other, _opts), do: nil

  defp digest(data, opts) do
    :hmac
    |> :crypto.mac(:sha256, Wiztchta.Config.secret_key_base!(opts), "wiztchta-client:" <> data)
    |> Base.url_encode64(padding: false)
  end
end
