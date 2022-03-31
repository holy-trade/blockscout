defmodule BlockScoutWeb.AddressEpochTransactionController do
  @moduledoc """
    Manages the displaying of information about epoch transactions as they relate to addresses
  """

  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain, only: [ next_page_params: 3, split_list_by_page: 1]

  alias BlockScoutWeb.{AccessHelpers, Controller, EpochTransactionView}
  alias Explorer.Celo.{ValidatorGroupRewards, ValidatorRewards, VoterRewards}
  alias Explorer.{Chain, Market}
  alias Explorer.Chain.Wei
  alias Explorer.ExchangeRates.Token
  alias Indexer.Fetcher.CoinBalanceOnDemand
  alias Phoenix.View

  def index(conn, %{"address_id" => address_hash_string, "type" => "JSON"} = params) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, address} <- Chain.hash_to_address(address_hash),
         {:ok, false} <- AccessHelpers.restricted_access?(address_hash_string, params) do
      epoch_transactions_object = calculate_based_on_account_type(address, params)
      epoch_transactions_plus_one = epoch_transactions_object.rewards
      {epoch_transactions, next_page} = split_list_by_page(epoch_transactions_plus_one)

      next_page_path =
        case next_page_params(next_page, epoch_transactions, params) do
          nil ->
            nil

          next_page_params ->
            address_epoch_transaction_path(conn, :index, address_hash, Map.delete(next_page_params, "type"))
        end

      epoch_transactions_json =
        Enum.map(epoch_transactions, fn epoch_transaction ->
          View.render_to_string(
            EpochTransactionView,
            "_tile.html",
            current_address: address,
            epoch_transaction: epoch_transaction
          )
        end)

      json(conn, %{items: epoch_transactions_json, next_page_path: next_page_path})
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        not_found(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  def index(conn, %{"address_id" => address_hash_string} = params) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, address} <- Chain.hash_to_address(address_hash),
         {:ok, false} <- AccessHelpers.restricted_access?(address_hash_string, params) do
      epoch_transactions = calculate_based_on_account_type(address)

      current_active_votes =
        if address.celo_account.account_type == "normal" do
          get_current_active_votes(epoch_transactions.rewards)
        else
          nil
        end

      render(
        conn,
        "index.html",
        address: address,
        coin_balance_status: CoinBalanceOnDemand.trigger_fetch(address),
        current_path: Controller.current_full_path(conn),
        exchange_rate: Market.get_exchange_rate("cGLD") || Token.null(),
        counters_path: address_path(conn, :address_counters, %{"id" => address_hash_string}),
        epoch_transactions: epoch_transactions,
        current_active_votes: current_active_votes,
        is_proxy: false
      )
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        not_found(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp calculate_based_on_account_type(address, params \\ %{}) do
    case address.celo_account.account_type do
      "normal" -> VoterRewards.calculate(address.hash, nil, nil, params)
      "validator" -> ValidatorRewards.calculate(address.hash, nil, nil, params)
      "group" -> ValidatorGroupRewards.calculate(address.hash, nil, nil)
    end
  end

  defp get_current_active_votes(rewards) do
    if Enum.empty?(rewards) do
      0
    else
      %{votes: %Wei{value: current_active_votes}} = rewards |> Enum.reverse() |> hd()
      current_active_votes
    end
  end
end
