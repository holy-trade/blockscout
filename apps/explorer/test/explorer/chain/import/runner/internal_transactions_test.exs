defmodule Explorer.Chain.Import.Runner.InternalTransactionsTest do
  use Explorer.DataCase

  alias Ecto.Multi
  alias Explorer.Chain.{Block, Data, Wei, PendingBlockOperation, Transaction, InternalTransaction}
  alias Explorer.Chain.Import.Runner.InternalTransactions

  describe "run/1" do
    test "transaction's status becomes :error when its internal_transaction has an error" do
      transaction = insert(:transaction) |> with_block(status: :ok)
      insert(:pending_block_operation, block_hash: transaction.block_hash, fetch_internal_transactions: true)

      assert :ok == transaction.status

      index = 0
      error = "Reverted"

      internal_transaction_changes = make_internal_transaction_changes(transaction, index, error)

      assert {:ok, _} = run_internal_transactions([internal_transaction_changes])

      assert :error == Repo.get(Transaction, transaction.hash).status
    end

    test "simple coin transfer's status becomes :error when its internal_transaction has an error" do
      transaction = insert(:transaction) |> with_block(status: :ok)
      insert(:pending_block_operation, block_hash: transaction.block_hash, fetch_internal_transactions: true)

      assert :ok == transaction.status

      index = 0
      error = "Out of gas"

      internal_transaction_changes =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction, index, error)

      assert {:ok, _} = run_internal_transactions([internal_transaction_changes])

      assert :error == Repo.get(Transaction, transaction.hash).status
    end

    test "for block with 2 simple coin transfer's statuses become :error when its both internal_transactions has an error" do
      a_block = insert(:block, number: 1000)
      transaction1 = insert(:transaction) |> with_block(a_block, status: :ok)
      transaction2 = insert(:transaction) |> with_block(a_block, status: :ok)

      insert(:pending_block_operation, block_hash: a_block.hash, fetch_internal_transactions: true)

      assert :ok == transaction1.status
      assert :ok == transaction2.status

      index = 0
      error = "Out of gas"

      internal_transaction_changes_1 =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction1, index, error)

      internal_transaction_changes_2 =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction2, index, error)

      assert {:ok, _} = run_internal_transactions([internal_transaction_changes_1, internal_transaction_changes_2])

      assert :error == Repo.get(Transaction, transaction1.hash).status
      assert :error == Repo.get(Transaction, transaction2.hash).status
    end

    test "for block with 2 simple coin transfer's only status become :error for tx where internal_transactions has an error" do
      a_block = insert(:block, number: 1000)
      transaction1 = insert(:transaction) |> with_block(a_block, status: :ok)
      transaction2 = insert(:transaction) |> with_block(a_block, status: :ok)
      insert(:pending_block_operation, block_hash: a_block.hash, fetch_internal_transactions: true)

      assert :ok == transaction1.status
      assert :ok == transaction2.status

      index = 0
      error = "Out of gas"

      internal_transaction_changes_1 =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction1, index, error)

      internal_transaction_changes_2 =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction2, index, nil)

      assert {:ok, _} = run_internal_transactions([internal_transaction_changes_1, internal_transaction_changes_2])

      assert :error == Repo.get(Transaction, transaction1.hash).status
      assert :ok == Repo.get(Transaction, transaction2.hash).status
    end

    test "for block with simple coin transfer and method calls, method calls internal txs have correct block_index" do
      a_block = insert(:block, number: 1000)
      transaction0 = insert(:transaction) |> with_block(a_block, status: :ok)
      transaction1 = insert(:transaction) |> with_block(a_block, status: :ok)
      transaction2 = insert(:transaction) |> with_block(a_block, status: :ok)
      insert(:pending_block_operation, block_hash: a_block.hash, fetch_internal_transactions: true)

      assert :ok == transaction0.status
      assert :ok == transaction1.status
      assert :ok == transaction2.status

      index = 0

      internal_transaction_changes_0 = make_internal_transaction_changes(transaction0, index, nil)
      internal_transaction_changes_0_1 = make_internal_transaction_changes(transaction0, 1, nil)

      internal_transaction_changes_1 =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction1, index, nil)

      internal_transaction_changes_2 = make_internal_transaction_changes(transaction2, index, nil)
      internal_transaction_changes_2_1 = make_internal_transaction_changes(transaction2, 1, nil)

      assert {:ok, _} =
               run_internal_transactions([
                 internal_transaction_changes_0,
                 internal_transaction_changes_0_1,
                 internal_transaction_changes_1,
                 internal_transaction_changes_2,
                 internal_transaction_changes_2_1
               ])

      assert from(i in InternalTransaction, where: i.transaction_hash == ^transaction0.hash, where: i.index == 0)
             |> Repo.one()
             |> is_nil()

      assert 1 == Repo.get_by!(InternalTransaction, transaction_hash: transaction0.hash, index: 1).block_index
      assert from(i in InternalTransaction, where: i.transaction_hash == ^transaction1.hash) |> Repo.one() |> is_nil()

      assert from(i in InternalTransaction, where: i.transaction_hash == ^transaction2.hash, where: i.index == 0)
             |> Repo.one()
             |> is_nil()

      assert 4 == Repo.get_by!(InternalTransaction, transaction_hash: transaction2.hash, index: 1).block_index
    end

    test "simple coin transfer has no internal transaction inserted" do
      transaction = insert(:transaction) |> with_block(status: :ok)
      insert(:pending_block_operation, block_hash: transaction.block_hash, fetch_internal_transactions: true)

      assert :ok == transaction.status

      index = 0

      internal_transaction_changes =
        make_internal_transaction_changes_for_simple_coin_transfers(transaction, index, nil)

      assert {:ok, _} = run_internal_transactions([internal_transaction_changes])

      assert !Repo.exists?(from(i in InternalTransaction, where: i.transaction_hash == ^transaction.hash))
    end

    test "pending transactions don't get updated not its internal_transactions inserted" do
      transaction = insert(:transaction) |> with_block(status: :ok)
      pending = insert(:transaction)

      insert(:pending_block_operation, block_hash: transaction.block_hash, fetch_internal_transactions: true)

      assert :ok == transaction.status
      assert is_nil(pending.block_hash)

      index = 1

      transaction_changes = make_internal_transaction_changes(transaction, index, nil)
      pending_changes = make_internal_transaction_changes(pending, index, nil)

      assert {:ok, _} = run_internal_transactions([transaction_changes, pending_changes])

      assert Repo.exists?(from(i in InternalTransaction, where: i.transaction_hash == ^transaction.hash))

      assert PendingBlockOperation |> Repo.get(transaction.block_hash) |> is_nil()

      assert from(i in InternalTransaction, where: i.transaction_hash == ^pending.hash) |> Repo.one() |> is_nil()

      assert is_nil(Repo.get(Transaction, pending.hash).block_hash)
    end

    test "removes consensus to blocks where transactions are missing" do
      empty_block = insert(:block)
      pending = insert(:transaction)

      insert(:pending_block_operation, block_hash: empty_block.hash, fetch_internal_transactions: true)

      assert is_nil(pending.block_hash)

      full_block = insert(:block)
      inserted = insert(:transaction) |> with_block(full_block)

      insert(:pending_block_operation, block_hash: full_block.hash, fetch_internal_transactions: true)

      assert full_block.hash == inserted.block_hash

      index = 1

      pending_transaction_changes =
        pending
        |> make_internal_transaction_changes(index, nil)
        |> Map.put(:block_number, empty_block.number)

      transaction_changes = make_internal_transaction_changes(inserted, index, nil)

      assert {:ok, _} = run_internal_transactions([pending_transaction_changes, transaction_changes])

      assert from(i in InternalTransaction, where: i.transaction_hash == ^pending.hash) |> Repo.one() |> is_nil()

      assert from(i in InternalTransaction, where: i.transaction_hash == ^inserted.hash) |> Repo.one() |> is_nil() ==
               false

      assert %{consensus: true} = Repo.get(Block, full_block.hash)
      assert PendingBlockOperation |> Repo.get(full_block.hash) |> is_nil()
    end

    test "removes old records with the same primary key (transaction_hash, index)" do
      full_block = insert(:block)
      another_full_block = insert(:block)

      transaction = insert(:transaction) |> with_block(full_block)

      insert(:internal_transaction,
        index: 0,
        transaction: transaction,
        block_hash: another_full_block.hash,
        block_index: 0
      )

      insert(:pending_block_operation, block_hash: full_block.hash, fetch_internal_transactions: true)

      transaction_changes = make_internal_transaction_changes(transaction, 0, nil)

      assert {:ok, %{remove_left_over_internal_transactions: {1, nil}}} =
               run_internal_transactions([transaction_changes])

      assert from(i in InternalTransaction,
               where: i.transaction_hash == ^transaction.hash and i.block_hash == ^another_full_block.hash
             )
             |> Repo.one()
             |> is_nil()
    end

    test "removes consensus to blocks where not all transactions are filled" do
      full_block = insert(:block)
      transaction_a = insert(:transaction) |> with_block(full_block)
      transaction_b = insert(:transaction) |> with_block(full_block)

      insert(:pending_block_operation, block_hash: full_block.hash, fetch_internal_transactions: true)

      transaction_a_changes = make_internal_transaction_changes(transaction_a, 0, nil)

      assert {:ok, _} = run_internal_transactions([transaction_a_changes])

      assert from(i in InternalTransaction, where: i.transaction_hash == ^transaction_a.hash) |> Repo.one() |> is_nil()
      assert from(i in InternalTransaction, where: i.transaction_hash == ^transaction_b.hash) |> Repo.one() |> is_nil()

      assert %{consensus: false} = Repo.get(Block, full_block.hash)
      assert not is_nil(Repo.get(PendingBlockOperation, full_block.hash))
    end

    test "does not remove consensus when block is empty and no transactions are missing" do
      empty_block = insert(:block)

      insert(:pending_block_operation, block_hash: empty_block.hash, fetch_internal_transactions: true)

      full_block = insert(:block)
      inserted = insert(:transaction) |> with_block(full_block)

      insert(:pending_block_operation, block_hash: full_block.hash, fetch_internal_transactions: true)

      assert full_block.hash == inserted.block_hash

      transaction_changes = make_internal_transaction_changes(inserted, 0, nil)
      transaction_changes_2 = make_internal_transaction_changes(inserted, 1, nil)
      empty_changes = make_empty_block_changes(empty_block.number)

      assert {:ok, _} = run_internal_transactions([empty_changes, transaction_changes, transaction_changes_2])

      assert %{consensus: true} = Repo.get(Block, empty_block.hash)
      assert PendingBlockOperation |> Repo.get(empty_block.hash) |> is_nil()

      assert from(i in InternalTransaction, where: i.transaction_hash == ^inserted.hash, where: i.index == 0)
             |> Repo.one()
             |> is_nil() ==
               true

      assert from(i in InternalTransaction, where: i.transaction_hash == ^inserted.hash, where: i.index == 1)
             |> Repo.one()
             |> is_nil() ==
               false

      assert %{consensus: true} = Repo.get(Block, full_block.hash)
      assert PendingBlockOperation |> Repo.get(full_block.hash) |> is_nil()
    end

    test "does not overwrite gas_used from transaction" do
      block = insert(:block)

      transaction =
        insert(:transaction,
          gas_used: 30_000,
          cumulative_gas_used: 30_000,
          index: 0,
          block_hash: block.hash,
          block_number: block.number
        )

      insert(:pending_block_operation, block_hash: block.hash, fetch_internal_transactions: true)

      transaction_changes = make_internal_transaction_changes(transaction, 0, nil)

      assert {:ok, _} = run_internal_transactions([transaction_changes])

      assert Repo.get(Transaction, transaction.hash).gas_used == Decimal.new(30_000)
      assert %{consensus: true} = Repo.get(Block, block.hash)
      assert is_nil(Repo.get(PendingBlockOperation, block.hash))
    end
  end

  defp run_internal_transactions(changes_list, multi \\ Multi.new()) when is_list(changes_list) do
    multi
    |> InternalTransactions.run(changes_list, %{
      timeout: :infinity,
      timestamps: %{inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
    })
    |> Repo.transaction()
  end

  defp make_empty_block_changes(block_number), do: %{block_number: block_number}

  defp make_internal_transaction_changes(transaction, index, error) do
    %{
      from_address_hash: insert(:address).hash,
      to_address_hash: insert(:address).hash,
      call_type: :call,
      gas: 22234,
      gas_used:
        if is_nil(error) do
          18920
        else
          nil
        end,
      input: %Data{bytes: <<1>>},
      output:
        if is_nil(error) do
          %Data{bytes: <<2>>}
        else
          nil
        end,
      index: index,
      trace_address: [],
      transaction_hash: transaction.hash,
      type: :call,
      value: Wei.from(Decimal.new(1), :wei),
      error: error,
      block_number: transaction.block_number
    }
  end

  defp make_internal_transaction_changes_for_simple_coin_transfers(transaction, index, error) do
    %{
      from_address_hash: insert(:address).hash,
      to_address_hash: insert(:address).hash,
      call_type: :call,
      gas: 0,
      gas_used: nil,
      input: %Data{bytes: <<>>},
      output:
        if is_nil(error) do
          %Data{bytes: <<0>>}
        else
          nil
        end,
      index: index,
      trace_address: [],
      transaction_hash: transaction.hash,
      type: :call,
      value: Wei.from(Decimal.new(1), :wei),
      error: error,
      block_number: transaction.block_number
    }
  end
end
