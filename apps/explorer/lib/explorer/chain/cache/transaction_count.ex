defmodule Explorer.Chain.Cache.TransactionCount do
  @moduledoc """
  Cache for estimated transaction count.
  """

  @default_cache_period :timer.hours(2)

  use Explorer.Chain.MapCache,
    name: :transaction_count,
    key: :count,
    key: :async_task,
    global_ttl: cache_period(),
    ttl_check_interval: :timer.minutes(15),
    callback: &async_task_on_deletion(&1)

  require Logger

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Transaction

  defp handle_fallback(:count) do
    # This will get the task PID if one exists and launch a new task if not
    # See next `handle_fallback` definition
    get_async_task()

    {:return, nil}
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists
    # so a new one needs to be launched
    {:ok, task} =
      Task.start(fn ->
        try do
          with {:ok, :nothing_running} <- query_db_for_running_tx_count_pids(),
              result <- query_db_for_exact_count() do

            params = %{
              counter_type: "total_transaction_count",
              value: result
            }

            Chain.upsert_last_fetched_counter(params)

            set_count(result)
          else
            {:updating, pods} ->
              Logger.info("Transaction count query is already running on pods #{Enum.join(pods, ",")}")
          end
        rescue
          e ->
            Logger.debug([
              "Coudn't update transaction count test #{inspect(e)}"
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

  defp cache_period do
    "TXS_COUNT_CACHE_PERIOD"
    |> System.get_env("")
    |> Integer.parse()
    |> case do
      {integer, ""} -> :timer.seconds(integer)
      _ -> @default_cache_period
    end
  end


  # getting count on a large table is very expensive and so we check for a process running on the db level
  # if so, we will refuse to launch another task and simply take the current estimated value until the running process has updated
  # the db
  defp query_db_for_running_tx_count_pids() do
    %{rows: results} = Ecto.Adapters.SQL.query!(Explorer.Repo, "SELECT application_name, pid
            FROM pg_stat_activity
            WHERE lower(query) like 'select count%from \"transactions\"%'")

    if length(results) == 0 do
      {:ok, :nothing_running}
    else
      pods = results |> Enum.map(fn [_pid, podname] -> podname end)
      {:updating, pods}
    end
  end

  defp query_db_for_exact_count() do
    Repo.aggregate(Transaction, :count, :hash, timeout: :infinity)
  end
end
