defmodule Wiztchta.RateLimiter.ETS do
  @moduledoc """
  Default in-memory `Wiztchta.RateLimiter`, local to each node.

  Uses fixed windows: one counter per key per window. A burst straddling a
  window boundary can briefly count up to twice the rate, which is fine for
  scaling difficulty. Started by the `:wiztchta` application; finished
  windows are swept every minute.
  """

  @behaviour Wiztchta.RateLimiter
  use GenServer

  @table :wiztchta_rate_counters
  @sweep_interval :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Wiztchta.RateLimiter
  def hit(key, window_seconds, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)
    window = div(now, window_seconds)
    window_ends_at = (window + 1) * window_seconds

    # Atomic increment; inserts {k, 0, ends_at} first if the key is new.
    :ets.update_counter(@table, {key, window}, {2, 1}, {{key, window}, 0, window_ends_at})
  end

  @doc false
  def sweep(now \\ System.system_time(:second)) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)
end
