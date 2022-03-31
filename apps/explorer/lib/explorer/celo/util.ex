defmodule Explorer.Celo.Util do
  @moduledoc """
  Utilities for reading from Celo smart contracts
  """
  import Ecto.Query,
    only: [
      from: 2,
      limit: 2,
      reverse_order: 1,
      where: 3
    ]

  require Logger
  alias Explorer.Celo.{AbiHandler, AddressCache, ContractEvents}
  alias Explorer.Chain.{Block, CeloContractEvent}
  alias Explorer.SmartContract.Reader

  alias ContractEvents.Common
  alias ContractEvents.Validators.ValidatorEpochPaymentDistributedEvent

  @celo_token_contract_symbols %{
    "stableToken" => "cUSD",
    "stableTokenEUR" => "cEUR",
    "stableTokenREAL" => "cREAL",
    # cGLD is the old symbol, needs to be updated to CELO
    "goldToken" => "cGLD"
  }

  def call_methods(methods) do
    contract_abi = AbiHandler.get_abi()

    methods
    |> Enum.map(&format_request/1)
    |> Enum.filter(fn req -> req.contract_address != :error end)
    |> Enum.map(fn %{contract_address: {:ok, address}} = req -> Map.put(req, :contract_address, address) end)
    |> Reader.query_contracts_by_name(contract_abi)
    |> Enum.zip(methods)
    |> Enum.into(%{}, fn
      {response, {_, function_name, _}} -> {function_name, response}
      {response, {_, function_name, _, _}} -> {function_name, response}
      {response, {_, _, _, _, custom_name}} -> {custom_name, response}
    end)
  end

  defp format_request({contract_name, function_name, params}) do
    %{
      contract_address: contract(contract_name),
      function_name: function_name,
      args: params
    }
  end

  defp format_request({contract_name, function_name, params, bn}) do
    %{
      contract_address: contract(contract_name),
      function_name: function_name,
      args: params,
      block_number: bn
    }
  end

  defp format_request({contract_name, function_name, params, bn, _}) do
    format_request({contract_name, function_name, params, bn})
  end

  defp contract(:blockchainparameters), do: get_address("BlockchainParameters")
  defp contract(:lockedgold), do: get_address("LockedGold")
  defp contract(:validators), do: get_address("Validators")
  defp contract(:election), do: get_address("Election")
  defp contract(:epochrewards), do: get_address("EpochRewards")
  defp contract(:accounts), do: get_address("Accounts")
  defp contract(:gold), do: get_address("GoldToken")
  defp contract(:usd), do: get_address("StableToken")
  defp contract(:eur), do: get_address("StableTokenEUR")
  defp contract(:reserve), do: get_address("Reserve")
  defp contract(:real), do: get_address("StableTokenREAL")

  def get_address(name) do
    case AddressCache.contract_address(name) do
      :error -> {:error}
      address -> {:ok, address}
    end
  end

  def get_token_contract_names do
    Map.keys(@celo_token_contract_symbols)
  end

  def get_token_contract_symbols do
    Map.values(@celo_token_contract_symbols)
  end

  def contract_name_to_symbol(name, use_celo_instead_cgld?) do
    case name do
      n when n in [nil, "goldToken"] ->
        if(use_celo_instead_cgld?, do: "CELO", else: "cGLD")

      _ ->
        @celo_token_contract_symbols[name]
    end
  end

  def epoch_by_block_number(bn) do
    div(bn, 17_280)
  end

  def add_input_account_to_individual_rewards_and_calculate_sum(reward_lists_chunked_by_account, key) do
    reward_lists_chunked_by_account
    |> Enum.map(fn x ->
      Map.put(
        x,
        :rewards,
        Enum.map(x.rewards, fn reward ->
          Map.put(reward, key, Map.get(x, key))
        end)
      )
    end)
    |> Enum.reduce([], fn curr, acc ->
      [curr.rewards | acc]
    end)
    |> List.flatten()
    |> Enum.sort_by(& &1.epoch_number)
    |> Enum.map_reduce(0, fn x, acc -> {x, acc + x.amount} end)
  end

  def set_default_from_and_to_dates_when_nil(from_date, to_date) do
    from_date =
      case from_date do
        nil -> ~U[2020-04-22 16:00:00.000000Z]
        from_date -> from_date
      end

    to_date =
      case to_date do
        nil -> DateTime.utc_now()
        to_date -> to_date
      end

    {from_date, to_date}
  end

  def structure_rewards(raw_rewards) do
    raw_rewards
    |> Enum.map(fn x ->
      Map.merge(
        x,
        %{
          epoch_number: epoch_by_block_number(x.block_number),
          group: Common.ca(x.group),
          validator: Common.ca(x.validator)
        }
      )
    end)
    |> Enum.map_reduce(0, fn x, acc -> {x, acc + x.amount} end)
  end

  def last_rewards(query, %{} = _params), do: query

  def last_rewards(query, %{"items_count" => limit, "epoch_number" => latest_epoch_number}) do
    query
    |> reverse_order()
    |> limit(^limit + 1)
    |> where([_event, block, _account], block.number < ^latest_epoch_number * 17280)
  end

  def last_rewards(query, %{"address_id" => _, "type" => _}), do: query |> reverse_order()
end
