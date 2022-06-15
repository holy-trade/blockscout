defmodule Explorer.Celo.VoterRewardsForGroup do
  @moduledoc """
    Module responsible for calculating a voter's rewards for a specific group. Extracted for testing purposes.
  """

  import Ecto.Query,
    only: [
      from: 2,
      limit: 2,
      reverse_order: 1,
      where: 3
    ]

  import Explorer.Celo.Util,
    only: [
      epoch_by_block_number: 1,
      set_default_from_and_to_dates_when_nil: 2
    ]

  alias Explorer.Celo.ContractEvents
  alias Explorer.Chain.{Block, CeloAccount, CeloContractEvent, CeloVoterVotes, Wei}
  alias Explorer.Repo

  alias ContractEvents.Election

  alias Election.{
    ValidatorGroupActiveVoteRevokedEvent,
    ValidatorGroupVoteActivatedEvent
  }

  @validator_group_vote_activated ValidatorGroupVoteActivatedEvent.topic()
  @validator_group_active_vote_revoked ValidatorGroupActiveVoteRevokedEvent.topic()
  @page_size 5

  def calculate(voter_address_hash, group_address_hash, from_date, to_date, params \\ []) do
    {from_date, to_date} = set_default_from_and_to_dates_when_nil(from_date, to_date)

    query = events_base_query()

    time_bound_events_query =
      set_start_and_end_for_events_query(query, from_date, to_date, params, voter_address_hash, group_address_hash)

    voter_activated_or_revoked_votes_for_group_events =
      time_bound_events_query
      |> CeloContractEvent.query_by_voter_param(voter_address_hash)
      |> CeloContractEvent.query_by_group_param(group_address_hash)
      |> Repo.all()

    # If no activated event present since genesis block, we don't have to look for votes for this voter/group pair
    if Enum.empty?(voter_activated_or_revoked_votes_for_group_events) and from_date == ~U[2020-04-22 16:00:00.000000Z] and
         Enum.empty?(params) do
      %{rewards: [], total: 0, group: group_address_hash}
    else
      query = votes_base_query(voter_address_hash, group_address_hash, to_date)

      votes_query_beginning_after_first_event_or_passed_from_date =
        set_start_and_end_for_votes_query(
          query,
          from_date,
          to_date,
          voter_activated_or_revoked_votes_for_group_events,
          params
        )

      voter_votes_for_group =
        votes_query_beginning_after_first_event_or_passed_from_date
        |> Repo.all()

      events_and_votes_chunked_by_epoch =
        if Enum.empty?(params) do
          merge_events_with_votes_and_chunk_by_epoch(
            voter_activated_or_revoked_votes_for_group_events,
            voter_votes_for_group
          )
        else
          merge_events_with_votes_and_chunk_by_epoch(
            Enum.reverse(voter_activated_or_revoked_votes_for_group_events),
            Enum.reverse(voter_votes_for_group)
          )
        end

      {rewards, {rewards_sum, _}} = calculate_rewards_and_rewards_sum(events_and_votes_chunked_by_epoch)

      # When from_date is different from the genesis block, the votes for one epoch prior to the time span's start is
      # necessary for the calculation. Here we remove this extra epoch after the rewards are calculated.
      {rewards, rewards_sum} = adjust_rewards_and_rewards_sum(from_date, rewards, rewards_sum, params)

      %CeloAccount{name: group_name} =
        Repo.one(from(account in CeloAccount, where: account.address == ^to_string(group_address_hash)))

      rewards =
        if Enum.empty?(params) do
          rewards
        else
          Enum.reverse(rewards)
        end

      %{rewards: rewards, total: rewards_sum, group: group_address_hash, group_name: group_name}
    end
  end

  defp calculate_rewards_and_rewards_sum(events_and_votes_chunked_by_epoch) do
    Enum.map_reduce(events_and_votes_chunked_by_epoch, {0, 0}, fn epoch, {rewards_sum, previous_epoch_votes} ->
      epoch_reward = calculate_single_epoch_reward(epoch, previous_epoch_votes)

      current_epoch_votes = epoch |> Enum.reverse() |> hd()
      %Wei{value: current_votes} = current_epoch_votes.votes
      current_votes_integer = Decimal.to_integer(current_votes)

      {
        %{
          amount: epoch_reward,
          block_hash: current_epoch_votes.block_hash,
          block_number: current_epoch_votes.block_number,
          date: current_epoch_votes.date,
          epoch_number: epoch_by_block_number(current_epoch_votes.block_number),
          votes: current_epoch_votes.votes
        },
        {epoch_reward + rewards_sum, current_votes_integer}
      }
    end)
  end

  def calculate_single_epoch_reward(epoch, previous_epoch_votes) do
    Enum.reduce(epoch, -previous_epoch_votes, fn
      %{votes: %Wei{value: votes}}, acc ->
        acc + Decimal.to_integer(votes)

      %{amount_activated_or_revoked: amount, event: @validator_group_vote_activated}, acc ->
        acc - amount

      %{amount_activated_or_revoked: amount, event: @validator_group_active_vote_revoked}, acc ->
        acc + amount
    end)
  end

  def merge_events_with_votes_and_chunk_by_epoch(events, votes) do
    chunk_fun = fn
      %{votes: _} = element, acc ->
        {:cont, Enum.reverse([element | acc]), []}

      element, acc ->
        {:cont, [element | acc]}
    end

    after_fun = fn
      [] -> {:cont, []}
      acc -> {:cont, Enum.reverse(acc), []}
    end

    (events ++ votes)
    |> Enum.sort_by(& &1.block_number)
    |> Enum.chunk_while([], chunk_fun, after_fun)
  end

  defp events_base_query do
    from(event in CeloContractEvent,
      inner_join: block in Block,
      on: event.block_number == block.number,
      select: %{
        amount_activated_or_revoked: json_extract_path(event.params, ["value"]),
        block_number: event.block_number,
        event: event.topic
      },
      order_by: [asc: event.block_number],
      where:
        event.topic == ^@validator_group_active_vote_revoked or
          event.topic == ^@validator_group_vote_activated
    )
  end

  defp set_start_and_end_for_events_query(query, from_date, to_date, [] = _params, _, _) do
    query
    |> where([_event, block], block.timestamp >= ^from_date)
    |> where([_event, block], block.timestamp < ^to_date)
  end

  defp set_start_and_end_for_events_query(query, _from_date, _to_date, %{"epoch_number" => latest_epoch_number}, _, _) do
    latest_epoch_number_int = String.to_integer(latest_epoch_number)

    query
    |> where([_event, block], block.number < ^latest_epoch_number_int * 17280)
    |> where([_event, block], block.number >= (^latest_epoch_number_int - @page_size - 1) * 17280)
    |> reverse_order()
  end

  defp set_start_and_end_for_events_query(
         query,
         _from_date,
         _to_date,
         %{"address_id" => _, "type" => _},
         voter_hash,
         group_hash
       ) do
    latest_activated_event =
      Repo.one(
        from(
          event in CeloContractEvent,
          where: fragment("? ->> ? = ?", event.params, "group", ^to_string(group_hash)),
          where: fragment("? ->> ? = ?", event.params, "address", ^to_string(voter_hash)),
          select: max(event.block_number)
        )
      )

    query
    |> where([_event, block], block.number >= (^latest_activated_event - @page_size - 1) * 17280)
    |> reverse_order()
  end

  defp votes_base_query(voter_address_hash, group_address_hash, _to_date) do
    from(votes in CeloVoterVotes,
      inner_join: block in Block,
      on: votes.block_hash == block.hash,
      select: %{
        block_hash: votes.block_hash,
        block_number: votes.block_number,
        date: block.timestamp,
        votes: votes.active_votes
      },
      where: votes.account_hash == ^voter_address_hash,
      where: votes.group_hash == ^group_address_hash
    )
  end

  defp set_start_and_end_for_votes_query(query, _, _, _, %{
         "epoch_number" => latest_epoch_number,
         "items_count" => limit
       }) do
    query
    |> reverse_order()
    |> limit(^limit + 1)
    |> where([votes, block], block.number < ^latest_epoch_number * 17280)
  end

  defp set_start_and_end_for_votes_query(query, _, _, _, %{"address_id" => _, "type" => _}) do
    query
    |> reverse_order()
  end

  defp set_start_and_end_for_votes_query(
         query,
         ~U[2020-04-22 16:00:00.000000Z] = _from_date,
         to_date,
         voter_activated_or_revoked_votes_for_group_events,
         _
       ) do
    [voter_activated_earliest_block | _] = voter_activated_or_revoked_votes_for_group_events

    query
    |> where([votes, _block], votes.block_number >= ^voter_activated_earliest_block.block_number)
    |> where([_votes, block], block.timestamp < ^to_date)
  end

  defp set_start_and_end_for_votes_query(query, from_date, to_date, _, _) do
    one_day_before_from_date = DateTime.add(from_date, -24 * 60 * 60)

    query
    |> where([_votes, block], block.timestamp >= ^one_day_before_from_date)
    |> where([_votes, block], block.timestamp < ^to_date)
  end

  defp adjust_rewards_and_rewards_sum(from_date, rewards, rewards_sum, _params) do
    if from_date == ~U[2020-04-22 16:00:00.000000Z] do
      {rewards, rewards_sum}
    else
      [first | rewards_without_the_first] = rewards
      rewards_sum_without_first = rewards_sum - first.amount
      {rewards_without_the_first, rewards_sum_without_first}
    end
  end
end
