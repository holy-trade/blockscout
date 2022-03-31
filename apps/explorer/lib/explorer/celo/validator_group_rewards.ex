defmodule Explorer.Celo.ValidatorGroupRewards do
  @moduledoc """
    Module responsible for calculating a validator's rewards for a given time frame.
  """
  import Ecto.Query,
    only: [
      join: 5,
      select_merge: 3
    ]

  alias Explorer.Repo
  alias Explorer.Chain.{CeloAccount, CeloContractEvent}
  alias Explorer.Celo.ContractEvents.Validators.ValidatorEpochPaymentDistributedEvent

  import Explorer.Celo.Util,
    only: [
      add_input_account_to_individual_rewards_and_calculate_sum: 2,
      last_rewards: 2,
      structure_rewards: 1,
      set_default_from_and_to_dates_when_nil: 2
    ]

  def calculate(group_address_hash, from_date, to_date, params \\ %{}) do
    {from_date, to_date} = set_default_from_and_to_dates_when_nil(from_date, to_date)

    query =
     ValidatorEpochPaymentDistributedEvent.base_query(from_date, to_date, "group")
      |> join(:inner, [event, block], account in CeloAccount,
        on: account.address == fragment("cast(?->>'validator' AS bytea)", event.params)
      )
      |> select_merge([_event, _block, account], %{validator_name: account.name})
      |> CeloContractEvent.query_by_group_param(group_address_hash)

    query_with_pagination = last_rewards(query, params)

    raw_rewards =
      query_with_pagination
      |> Repo.all()

    res = structure_rewards(raw_rewards)

    res
    |> then(fn {rewards, total} ->
      %{
        from: from_date,
        rewards: Enum.map(rewards, &Map.delete(&1, :group)),
        to: to_date,
        total_reward_celo: total,
        group: group_address_hash
      }
    end)
  end

  def calculate_multiple_accounts(voter_address_hash_list, from_date, to_date) do
    reward_lists_chunked_by_account =
      voter_address_hash_list
      |> Enum.map(fn hash -> calculate(hash, from_date, to_date) end)

    {rewards, rewards_sum} =
      add_input_account_to_individual_rewards_and_calculate_sum(reward_lists_chunked_by_account, :group)

    %{from: from_date, to: to_date, rewards: rewards, total_reward_celo: rewards_sum}
  end
end
