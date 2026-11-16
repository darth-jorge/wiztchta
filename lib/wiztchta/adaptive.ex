defmodule Wiztchta.Adaptive do
  @moduledoc """
  Adaptive difficulty: the more challenges a visitor was issued recently,
  the harder their next proof-of-work gets. Nobody is blocked; heavy use
  just costs more CPU per form.

  Each challenge issued to a visitor (see `Wiztchta.ClientKey`) is counted
  per fixed window. The first `:rate_free` in a window cost nothing extra;
  after that every doubling adds one bit (twice the work):

  | challenges in the window | extra bits | work |
  |---|---|---|
  | 1–5 | 0 | 1× |
  | 6–10 | 1 | 2× |
  | 11–20 | 2 | 4× |
  | 21–40 | 3 | 8× |
  | 41+ | 4+ | capped by `:pow_max_difficulty` |

  The extra bits are passed to the challenge type's `generate/1` as
  `:pressure`; `Wiztchta.Challenges.ProofOfWork` adds them to its
  difficulty, other types may ignore them.

  ## Options

    * `:client` - the visitor's key. Defaults to the one recorded by the
      `Wiztchta.ClientKey` plug; `false` disables adaptation for a call.
    * `:rate_limiter` - defaults to `Wiztchta.RateLimiter.ETS`; `nil` disables.
    * `:rate_window` - window length in seconds. Defaults to `600`.
    * `:rate_free` - challenges per window without extra work. Defaults to `5`.

  Without a client key (no plug, LiveView without `client:`) nothing changes.
  """

  alias Wiztchta.{ClientKey, Config}

  @doc "Counts a new challenge for the visitor and returns its pressure."
  @spec pressure(keyword) :: non_neg_integer
  def pressure(opts) do
    with client when is_binary(client) <- client!(opts),
         limiter when not is_nil(limiter) and limiter != false <- Config.get(:rate_limiter, opts) do
      window = positive!(:rate_window, Config.get(:rate_window, opts))
      free = positive!(:rate_free, Config.get(:rate_free, opts))

      client
      |> limiter.hit(window, opts)
      |> pressure_for(free)
    else
      _ -> 0
    end
  end

  @doc """
  Extra bits for `count` challenges in a window with `free` allowed:
  0 up to `free`, then the smallest `k` with `free * 2^k >= count`.
  """
  @spec pressure_for(pos_integer, pos_integer) :: non_neg_integer
  def pressure_for(count, free) when count <= free, do: 0
  def pressure_for(count, free) when free > 0, do: 1 + pressure_for(count, free * 2)

  # free = 0 would recurse forever (0 * 2 == 0); fail loudly instead.
  defp positive!(_name, value) when is_integer(value) and value > 0, do: value

  defp positive!(name, value) do
    raise ArgumentError, "#{inspect(name)} must be a positive integer, got: #{inspect(value)}"
  end

  defp client!(opts) do
    case Keyword.fetch(opts, :client) do
      :error ->
        ClientKey.current()

      {:ok, nil} ->
        nil

      {:ok, false} ->
        nil

      {:ok, key} when is_binary(key) and key != "" ->
        key

      {:ok, other} ->
        raise ArgumentError, ":client must be a string, nil or false, got: #{inspect(other)}"
    end
  end
end
