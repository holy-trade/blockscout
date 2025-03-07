defmodule BlockScoutWeb.AddressSignedController do
  @moduledoc """
  Display all the blocks that this address was elected to sign.
  """
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [paging_options: 1, next_page_params: 3, split_list_by_page: 1]

  alias BlockScoutWeb.{AccessHelpers, BlockView}
  alias Explorer.ExchangeRates.Token
  alias Explorer.{Chain, Market}
  alias Indexer.Fetcher.CoinBalanceOnDemand
  alias Phoenix.View

  def index(conn, %{"address_id" => address_hash_string, "type" => "JSON"} = params) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, _} <- Chain.find_or_insert_address_from_hash(address_hash, [], false),
         {:ok, false} <- AccessHelpers.restricted_access?(address_hash_string, params) do
      full_options =
        Keyword.merge(
          [
            necessity_by_association: %{
              miner: :required,
              nephews: :optional,
              transactions: :optional,
              rewards: :optional
            }
          ],
          paging_options(params)
        )

      blocks_plus_one = Chain.get_downtime_by_address(full_options, address_hash)
      {blocks, next_page} = split_list_by_page(blocks_plus_one)

      next_page_path =
        case next_page_params(next_page, blocks, params) do
          nil ->
            nil

          next_page_params ->
            address_signed_path(
              conn,
              :index,
              address_hash_string,
              Map.delete(next_page_params, "type")
            )
        end

      items =
        Enum.map(blocks, fn block ->
          View.render_to_string(
            BlockView,
            "_tile.html",
            conn: conn,
            block: block,
            block_type: BlockView.block_type(block)
          )
        end)

      json(conn, %{items: items, next_page_path: next_page_path})
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        unprocessable_entity(conn)
    end
  end

  def index(conn, %{"address_id" => address_hash_string} = params) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(address_hash_string),
         {:ok, address} <- Chain.find_or_insert_address_from_hash(address_hash),
         {:ok, false} <- AccessHelpers.restricted_access?(address_hash_string, params) do
      render(
        conn,
        "index.html",
        address: address,
        coin_balance_status: CoinBalanceOnDemand.trigger_fetch(address),
        current_path: current_path(conn),
        counters_path: address_path(conn, :address_counters, %{"id" => address_hash_string}),
        exchange_rate: Market.get_exchange_rate(Explorer.coin()) || Token.null()
      )
    else
      {:restricted_access, _} ->
        not_found(conn)

      :error ->
        unprocessable_entity(conn)

      {:error, :not_found} ->
        not_found(conn)
    end
  end
end
