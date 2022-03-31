defmodule Explorer.Celo.ValidatorRewards do
  @moduledoc """
    Module responsible for calculating a validator's rewards for a given time frame.
  """

  import Ecto.Query

  alias Explorer.Repo
  alias Explorer.Chain.{Block, CeloAccount}
  alias Explorer.Celo.ContractEvents.Validators.ValidatorEpochPaymentDistributedEvent

  import Explorer.Celo.Util,
    only: [
      add_input_account_to_individual_rewards_and_calculate_sum: 2,
      last_rewards: 2,
      structure_rewards: 1,
      set_default_from_and_to_dates_when_nil: 2
    ]

  def calculate(validator_address_hash, from_date, to_date, params \\ %{show_empty: true}) do
    {from_date, to_date} = set_default_from_and_to_dates_when_nil(from_date, to_date)

    base_query =
      ValidatorEpochPaymentDistributedEvent.query()
      |> ValidatorEpochPaymentDistributedEvent.query_by_validator(validator_address_hash)
      |> join(:inner, [event], account in CeloAccount,
        as: :account,
        on: account.address == fragment("cast(?->>'group' AS bytea)", event.params)
      )
      |> join(:inner, [event], block in Block,
        as: :block,
        on: block.number == event.block_number
      )

    filtered_query =
      base_query
      |> where([event, block: b], fragment("? BETWEEN ? and ? ", b.timestamp, ^from_date, ^to_date))
      |> select([event, account: account, block: block], %{
        amount: json_extract_path(event.params, ["validator_payment"]),
        date: block.timestamp,
        block_number: block.number,
        block_hash: block.hash,
        group: json_extract_path(event.params, ["group"]),
        validator: json_extract_path(event.params, ["validator"]),
        group_name: account.name
      })
      |> order_by([result], result.block_number)

    filtered_query =
      if Map.get(params, :show_empty) === false do
        filtered_query |> where([event], fragment("ROUND((? ->> ?)::numeric) != 0", event.params, "validator_payment"))
      else
        filtered_query
      end

    query_with_pagination = last_rewards(filtered_query, params)

    raw_rewards =
      query_with_pagination
      |> Repo.all()

    res = structure_rewards(raw_rewards)

    res
    |> then(fn {rewards, total} ->
      %{
        account: validator_address_hash,
        from: from_date,
        rewards: Enum.map(rewards, &Map.delete(&1, :validator)),
        to: to_date,
        total_reward_celo: total
      }
    end)
  end

  def calculate_multiple_accounts(voter_address_hash_list, from_date, to_date) do
    reward_lists_chunked_by_account =
      voter_address_hash_list
      |> Enum.map(fn hash -> calculate(hash, from_date, to_date) end)

    {rewards, rewards_sum} =
      add_input_account_to_individual_rewards_and_calculate_sum(reward_lists_chunked_by_account, :account)

    %{from: from_date, to: to_date, rewards: rewards, total_reward_celo: rewards_sum}
  end
end
