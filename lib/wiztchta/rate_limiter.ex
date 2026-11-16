defmodule Wiztchta.RateLimiter do
  @moduledoc """
  Behaviour for counting how many challenges a visitor was issued recently,
  which drives adaptive difficulty (see `Wiztchta.Adaptive`).

  The default, `Wiztchta.RateLimiter.ETS`, counts in memory on the local
  node. Behind a load balancer each node counts separately; plug in a shared
  counter (Redis, etc.) for cluster-wide counts:

      config :wiztchta, rate_limiter: MyApp.WiztchtaRedisLimiter

  Set `rate_limiter: nil` to disable adaptive difficulty.
  """

  @doc """
  Increments the counter for `key` in the current fixed window of
  `window_seconds` and returns the new count.
  """
  @callback hit(key :: String.t(), window_seconds :: pos_integer, opts :: keyword) ::
              pos_integer
end
