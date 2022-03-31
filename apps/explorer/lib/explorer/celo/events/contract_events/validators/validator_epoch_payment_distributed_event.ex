defmodule Explorer.Celo.ContractEvents.Validators.ValidatorEpochPaymentDistributedEvent do
  @moduledoc """
  Struct modelling the Validators.ValidatorEpochPaymentDistributed event

  ValidatorEpochPaymentDistributed(
        address indexed validator,
        uint256 validatorPayment,
        address indexed group,
        uint256 groupPayment
    );
  """

  use Explorer.Celo.ContractEvents.Base,
    name: "ValidatorEpochPaymentDistributed",
    topic: "0x6f5937add2ec38a0fa4959bccd86e3fcc2aafb706cd3e6c0565f87a7b36b9975"

  event_param(:validator, :address, :indexed)
  event_param(:group, :address, :indexed)
  event_param(:validator_payment, {:uint, 256}, :unindexed)
  event_param(:group_payment, {:uint, 256}, :unindexed)


  alias Explorer.Chain.Block

  def base_query(from_date, to_date, "validator"), do: base_query(from_date, to_date, "validator_payment")
  def base_query(from_date, to_date, "group"), do: base_query(from_date, to_date, "group_payment")
  def base_query(from_date, to_date, payment) do
    from(event in CeloContractEvent,
      inner_join: block in Block,
      on: event.block_number == block.number,
      select: %{
        amount: json_extract_path(event.params, [^payment]),
        date: block.timestamp,
        block_number: block.number,
        block_hash: block.hash,
        group: json_extract_path(event.params, ["group"]),
        validator: json_extract_path(event.params, ["validator"])
      },
      order_by: [asc: block.number],
      where: event.topic == ^@topic,
      where: block.timestamp >= ^from_date,
      where: block.timestamp < ^to_date,
      where: fragment("ROUND((? ->> ?)::numeric) != 0", event.params, ^payment)
    )
  end
end
