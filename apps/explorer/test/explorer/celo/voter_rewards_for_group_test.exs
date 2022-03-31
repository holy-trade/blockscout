defmodule Explorer.Celo.VoterRewardsForGroupTest do
  use Explorer.DataCase

  alias Explorer.Celo.VoterRewardsForGroup
  alias Explorer.Chain.{Hash, Wei}
  alias Explorer.SetupVoterRewardsTest

  describe "calculate/2" do
    test "when no from_date and to_date passed" do
      {
        voter_hash,
        group_hash,
        group_name,
        block_2_hash,
        block_3_hash,
        block_5_hash,
        block_7_hash
      } = SetupVoterRewardsTest.setup_for_group()

      rewards = VoterRewardsForGroup.calculate(voter_hash, group_hash, nil, nil)

      assert rewards ==
               %{
                 group: group_hash,
                 group_name: group_name,
                 total: 175,
                 rewards: [
                   %{
                     amount: 80,
                     block_hash: block_2_hash,
                     block_number: 10_696_320,
                     date: ~U[2022-01-01 17:42:43.162804Z],
                     epoch_number: 619,
                     votes: %Wei{value: Decimal.new(730)}
                   },
                   %{
                     amount: 20,
                     block_hash: block_3_hash,
                     block_number: 10_713_600,
                     date: ~U[2022-01-02 17:42:43.162804Z],
                     epoch_number: 620,
                     votes: %Wei{value: Decimal.new(750)}
                   },
                   %{
                     amount: 75,
                     block_hash: block_5_hash,
                     block_number: 10_730_880,
                     date: ~U[2022-01-03 17:42:43.162804Z],
                     epoch_number: 621,
                     votes: %Wei{value: Decimal.new(1075)}
                   },
                   %{
                     amount: 0,
                     block_hash: block_7_hash,
                     block_number: 10_748_160,
                     date: ~U[2022-01-04 17:42:43.162804Z],
                     epoch_number: 622,
                     votes: %Wei{value: Decimal.new(0)}
                   }
                 ]
               }
    end

    test "when from_date and to_date passed" do
      {
        voter_hash,
        group_hash,
        group_name,
        _block_2_hash,
        block_3_hash,
        block_5_hash,
        _block_7_hash
      } = SetupVoterRewardsTest.setup_for_group()

      rewards =
        VoterRewardsForGroup.calculate(
          voter_hash,
          group_hash,
          ~U[2022-01-02 00:00:00.000000Z],
          ~U[2022-01-04 00:00:00.000000Z]
        )

      assert rewards ==
               %{
                 group: group_hash,
                 group_name: group_name,
                 total: 95,
                 rewards: [
                   %{
                     amount: 20,
                     block_hash: block_3_hash,
                     block_number: 10_713_600,
                     date: ~U[2022-01-02 17:42:43.162804Z],
                     epoch_number: 620,
                     votes: %Wei{value: Decimal.new(750)}
                   },
                   %{
                     amount: 75,
                     block_hash: block_5_hash,
                     block_number: 10_730_880,
                     date: ~U[2022-01-03 17:42:43.162804Z],
                     epoch_number: 621,
                     votes: %Wei{value: Decimal.new(1075)}
                   }
                 ]
               }
    end
  end

  describe "merge_events_with_votes_and_chunk_by_epoch/2" do
    test "when voter first activated on an epoch block" do
      # Block hash is irrelevant in the context of the test so the same one is used everywhere for readability
      block_hash = %Hash{
        byte_count: 32,
        bytes: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
      }

      events = [
        %{
          amount_activated_or_revoked: 650,
          block_hash: block_hash,
          block_number: 618 * 17_280,
          event: "ValidatorGroupVoteActivated"
        },
        %{
          amount_activated_or_revoked: 650,
          block_hash: block_hash,
          block_number: 618 * 17_280 + 1,
          event: "ValidatorGroupActiveVoteRevoked"
        },
        %{
          amount_activated_or_revoked: 250,
          block_hash: block_hash,
          block_number: 621 * 17_280 - 1,
          event: "ValidatorGroupVoteActivated"
        },
        %{
          amount_activated_or_revoked: 1075,
          block_hash: block_hash,
          block_number: 622 * 17_280 - 1,
          event: "ValidatorGroupActiveVoteRevoked"
        }
      ]

      votes = [
        %{
          block_hash: block_hash,
          block_number: 619 * 17_280,
          date: ~U[2022-01-01 17:42:43.162804Z],
          votes: %Wei{value: 730}
        },
        %{
          block_hash: block_hash,
          block_number: 620 * 17_280,
          date: ~U[2022-01-02 17:42:43.162804Z],
          votes: %Wei{value: 750}
        },
        %{
          block_hash: block_hash,
          block_number: 621 * 17_280,
          date: ~U[2022-01-03 17:42:43.162804Z],
          votes: %Wei{value: 1075}
        },
        %{
          block_hash: block_hash,
          block_number: 622 * 17_280,
          date: ~U[2022-01-04 17:42:43.162804Z],
          votes: %Wei{value: 0}
        }
      ]

      assert VoterRewardsForGroup.merge_events_with_votes_and_chunk_by_epoch(events, votes) == [
               [
                 %{
                   amount_activated_or_revoked: 650,
                   block_hash: block_hash,
                   block_number: 618 * 17_280,
                   event: "ValidatorGroupVoteActivated"
                 },
                 %{
                   amount_activated_or_revoked: 650,
                   block_hash: block_hash,
                   block_number: 618 * 17_280 + 1,
                   event: "ValidatorGroupActiveVoteRevoked"
                 },
                 %{
                   block_hash: block_hash,
                   block_number: 619 * 17_280,
                   date: ~U[2022-01-01 17:42:43.162804Z],
                   votes: %Wei{value: 730}
                 }
               ],
               [
                 %{
                   block_hash: block_hash,
                   block_number: 620 * 17_280,
                   date: ~U[2022-01-02 17:42:43.162804Z],
                   votes: %Wei{value: 750}
                 }
               ],
               [
                 %{
                   amount_activated_or_revoked: 250,
                   block_hash: block_hash,
                   block_number: 621 * 17_280 - 1,
                   event: "ValidatorGroupVoteActivated"
                 },
                 %{
                   block_hash: block_hash,
                   block_number: 621 * 17_280,
                   date: ~U[2022-01-03 17:42:43.162804Z],
                   votes: %Wei{value: 1075}
                 }
               ],
               [
                 %{
                   amount_activated_or_revoked: 1075,
                   block_hash: block_hash,
                   block_number: 622 * 17_280 - 1,
                   event: "ValidatorGroupActiveVoteRevoked"
                 },
                 %{
                   block_hash: block_hash,
                   block_number: 622 * 17_280,
                   date: ~U[2022-01-04 17:42:43.162804Z],
                   votes: %Wei{value: 0}
                 }
               ]
             ]
    end
  end
end
