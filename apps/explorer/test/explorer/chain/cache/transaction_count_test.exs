defmodule Explorer.Chain.Cache.TransactionCountTest do
  use Explorer.DataCase

  alias Explorer.Chain.Cache.TransactionCount
  alias Explorer.Counters.LastFetchedCounter

  setup do
    Supervisor.terminate_child(Explorer.Supervisor, TransactionCount.child_id())
    Supervisor.restart_child(Explorer.Supervisor, TransactionCount.child_id())
    :ok
  end

  test "returns default transaction count" do
    result = TransactionCount.get_count()

    assert is_nil(result)
  end

  test "updates cache if initial value is zero" do
    insert(:transaction)
    insert(:transaction)

    result = TransactionCount.get_count()
    assert is_nil(result)

    Process.sleep(1000)

    counter = Repo.one!(from(c in LastFetchedCounter, where: c.counter_type == "total_transaction_count"))
    assert 2 == Decimal.to_integer(counter.value)

    updated_value = TransactionCount.get_count()

    assert updated_value == 2
  end

  test "does not update cache if cache period did not pass" do
    insert(:transaction)
    insert(:transaction)

    _result = TransactionCount.get_count()

    Process.sleep(1000)

    updated_value = TransactionCount.get_count()

    assert updated_value == 2

    insert(:transaction)
    insert(:transaction)

    _updated_value = TransactionCount.get_count()

    Process.sleep(1000)

    updated_value = TransactionCount.get_count()

    assert updated_value == 2
  end

  test "does not run if 'other' tx count query is running" do
    #fake a long running tx count query
    {:ok, pid} = Task.Supervisor.start_child(Explorer.TaskSupervisor, fn ->
      # checkout a different db connection so it can be intentionally held
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Explorer.Repo)
      Ecto.Adapters.SQL.query!(Explorer.Repo, "SELECT count(*), pg_sleep(5) from \"transactions\"")
    end)

    Process.sleep(100)

    running_queries = TransactionCount.query_db_for_running_tx_count_pids()
    result = TransactionCount.get_count()

    # should indicate a query is running
    assert {:running, _} = running_queries
    assert nil == result

    # should not pick up new transactions yet
    insert(:transaction)
    insert(:transaction)

    result = TransactionCount.get_count()
    assert nil == result

    # kill the slow db query task
    Process.exit(pid, :shutdown)
  end
end
