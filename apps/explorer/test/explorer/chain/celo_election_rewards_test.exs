defmodule Explorer.Chain.CeloElectionRewardsTest do
  use Explorer.DataCase

  import Explorer.Factory

  alias Explorer.Chain
  alias Explorer.Chain.Wei

  alias Chain.{Address, Block, CeloElectionRewards}

  describe "get_rewards/2" do
    test "returns rewards for an account that has both voter and validator rewards" do
      %Address{hash: account_hash} = insert(:address)
      %Address{hash: group_hash} = insert(:address)
      insert(:celo_account, address: group_hash)
      %Block{number: block_number, timestamp: block_timestamp} = insert(:block, number: 17_280)

      insert(
        :celo_election_rewards,
        account_hash: account_hash,
        associated_account_hash: group_hash,
        block_number: block_number,
        block_timestamp: block_timestamp
      )

      insert(
        :celo_election_rewards,
        account_hash: account_hash,
        associated_account_hash: group_hash,
        block_number: block_number,
        block_timestamp: block_timestamp,
        reward_type: "validator"
      )

      {:ok, one_wei} = Wei.cast(1)

      assert CeloElectionRewards.get_rewards([account_hash], ["voter", "validator"]) == [
               %{
                 account_hash: account_hash,
                 amount: one_wei,
                 associated_account_hash: group_hash,
                 block_number: block_number,
                 date: block_timestamp,
                 epoch_number: 1,
                 reward_type: "validator"
               },
               %{
                 account_hash: account_hash,
                 amount: one_wei,
                 associated_account_hash: group_hash,
                 block_number: block_number,
                 date: block_timestamp,
                 epoch_number: 1,
                 reward_type: "voter"
               }
             ]
    end
  end
end
