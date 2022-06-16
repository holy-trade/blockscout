defmodule Explorer.Chain.Cache.TransactionCount do
  @moduledoc """
  Cache for estimated transaction count.
  """

  @default_cache_period :timer.hours(2)

  use Explorer.Chain.MapCache,
    name: :transaction_count,
    key: :count,
    key: :async_task,
    global_ttl: get_cache_period(),
    ttl_check_interval: :timer.minutes(15),
    callback: &async_task_on_deletion(&1)

  require Logger

  alias Ecto.Adapters.SQL
  alias Explorer.Celo.Telemetry
  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Transaction
  alias Explorer.Counters.LastFetchedCounter
  import Ecto.Query

  @transaction_counter_type "total_transaction_count"
  defp handle_fallback(:count) do
    # This will get the task PID if one exists and launch a new task if not
    # See next `handle_fallback` definition
    get_async_task()

    {:return, nil}
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists on this beam instance
    # so a new one needs to be launched
    {:ok, task} =
      Task.start(fn ->
        try do
          # run the tx count query iff
          # 1. the value currently cached in the db is older than `cache_period` (db time)
          # 2. there same query is not currently running on the db (if so, that value will be retrieved from a future step 1)
          with {:stale} <- query_db_for_cache(),
               {:ok, :nothing_running} <- query_db_for_running_tx_count_pids(),
               result <- query_db_for_exact_count() do
            set_db_cache(result)
            set_count(result)
          else
            {:running, apps} ->
              Logger.info("Transaction count query is already running on apps: #{Enum.join(apps, ",")}")

            {:fresh_db_cache, value} ->
              set_count(value)
          end
        rescue
          e ->
            Logger.debug([
              "Couldn't update transaction count test #{inspect(e)}"
            ])
        end

        set_async_task(nil)
      end)

    {:update, task}
  end

  # By setting this as a `callback` an async task will be started each time the
  # `count` expires (unless there is one already running)
  defp async_task_on_deletion({:delete, _, :count}), do: get_async_task()

  defp async_task_on_deletion(_data), do: nil

  defp get_cache_period do
    "TXS_COUNT_CACHE_PERIOD"
    |> System.get_env("")
    |> Integer.parse()
    |> case do
      {integer, ""} -> :timer.seconds(integer)
      _ -> @default_cache_period
    end
  end

  defp set_db_cache(tx_count) do
    params = %{
      counter_type: "total_transaction_count",
      value: tx_count
    }

    Chain.upsert_last_fetched_counter(params)
  end

  # getting count on a large table is very expensive and so we check for a process running on the db level
  # if so, we will refuse to launch another task and simply take the current estimated value until the running process has updated
  # the db
  def query_db_for_running_tx_count_pids do
    %{rows: results} = SQL.query!(Repo, "SELECT application_name
            FROM pg_stat_activity
            WHERE lower(query) like 'select count%\"transactions\"%'
            and lower(query) not like '%where%'")

    if Enum.empty?(results) do
      {:ok, :nothing_running}
    else
      {:running, results}
    end
  end

  # run the count(hash) query
  def query_db_for_exact_count do
    start = Telemetry.start(:tx_count_query)
    result = Repo.aggregate(Transaction, :count, :hash, timeout: :infinity)
    stop = Telemetry.stop(:tx_count_query, start)
    duration = System.convert_time_unit(stop - start, :native, :milliseconds)

    Logger.info("Retrieved transaction count #{result} took #{duration} ms")

    result
  end

  # check for a valid cached value
  def query_db_for_cache do
    query =
      from(
        last_fetched_counter in LastFetchedCounter,
        where: last_fetched_counter.counter_type == ^@transaction_counter_type,
        select:
          {last_fetched_counter.value,
           fragment("extract(epoch from (now() - (?))) * 1000 as milliseconds_old", last_fetched_counter.updated_at)}
      )

    fetched_result = query |> Repo.one()

    # local so that value can be used in guard clause
    cache_period = get_cache_period()

    case fetched_result do
      nil ->
        {:stale}

      {_value, how_old_ms} when how_old_ms > cache_period ->
        Logger.info(
          "Transaction count cache is #{how_old_ms |> round()} ms old and above configured cache period #{cache_period} ms"
        )

        {:stale}

      {value, _how_old_ms} ->
        {:fresh_db_cache, value |> Decimal.to_integer()}
    end
  end
end
