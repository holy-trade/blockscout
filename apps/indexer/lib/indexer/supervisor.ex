defmodule Indexer.Supervisor do
  @moduledoc """
  Supervisor of all indexer worker supervision trees
  """

  use Supervisor

  alias Explorer.Celo.InternalTransactionCache

  alias Explorer.Chain

  alias Indexer.{
    Block,
    CalcLpTokensTotalLiqudity,
    PendingOpsCleaner,
    PendingTransactionsSanitizer,
    SetAmbBridgedMetadataForTokens,
    SetOmniBridgedMetadataForTokens
  }

  alias Indexer.Block.{Catchup, Realtime}

  alias Indexer.Fetcher.{
    BlockReward,
    CeloAccount,
    CeloElectionRewards,
    CeloEpochRewards,
    CeloMaterializedViewRefresh,
    CeloUnlocked,
    CeloValidator,
    CeloValidatorGroup,
    CeloValidatorHistory,
    CeloVoters,
    CoinBalance,
    CoinBalanceOnDemand,
    ContractCode,
    EmptyBlocksSanitizer,
    InternalTransaction,
    PendingTransaction,
    ReplacedTransaction,
    Token,
    TokenBalance,
    TokenInstance,
    TokenTotalSupplyOnDemand,
    TokenUpdater,
    UncleBlock
  }

  alias Indexer.Temporary.{
    BlocksTransactionsMismatch,
    UncatalogedTokenTransfers,
    UnclesWithoutIndex
  }

  alias Indexer.Prometheus.MetricsCron

  def child_spec([]) do
    child_spec([[]])
  end

  def child_spec([init_arguments]) do
    child_spec([init_arguments, []])
  end

  def child_spec([_init_arguments, _gen_server_options] = start_link_arguments) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_link_arguments},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  def start_link(arguments, gen_server_options \\ []) do
    Supervisor.start_link(__MODULE__, arguments, Keyword.put_new(gen_server_options, :name, __MODULE__))
  end

  @impl Supervisor
  def init(%{memory_monitor: memory_monitor}) do
    json_rpc_named_arguments = Application.fetch_env!(:indexer, :json_rpc_named_arguments)

    named_arguments =
      :indexer
      |> Application.get_all_env()
      |> Keyword.take(
        ~w(blocks_batch_size blocks_concurrency block_interval json_rpc_named_arguments receipts_batch_size
           receipts_concurrency subscribe_named_arguments realtime_overrides)a
      )
      |> Enum.into(%{})
      |> Map.put(:memory_monitor, memory_monitor)
      |> Map.put_new(:realtime_overrides, %{})

    %{
      block_interval: block_interval,
      realtime_overrides: realtime_overrides,
      subscribe_named_arguments: subscribe_named_arguments
    } = named_arguments

    block_fetcher =
      named_arguments
      |> Map.drop(~w(block_interval blocks_concurrency memory_monitor subscribe_named_arguments realtime_overrides)a)
      |> Block.Fetcher.new()

    realtime_block_fetcher =
      named_arguments
      |> Map.drop(~w(block_interval blocks_concurrency memory_monitor subscribe_named_arguments realtime_overrides)a)
      |> Map.merge(Enum.into(realtime_overrides, %{}))
      |> Block.Fetcher.new()

    realtime_subscribe_named_arguments = realtime_overrides[:subscribe_named_arguments] || subscribe_named_arguments

    basic_fetchers = [
      # Root fetchers
      {PendingTransaction.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments]]},
      {Realtime.Supervisor,
       [
         %{block_fetcher: realtime_block_fetcher, subscribe_named_arguments: realtime_subscribe_named_arguments},
         [name: Realtime.Supervisor]
       ]},
      {Catchup.Supervisor,
       [
         %{block_fetcher: block_fetcher, block_interval: block_interval, memory_monitor: memory_monitor},
         [name: Catchup.Supervisor]
       ]},

      # Async catchup fetchers
      {UncleBlock.Supervisor, [[block_fetcher: block_fetcher, memory_monitor: memory_monitor]]},
      {BlockReward.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {InternalTransaction.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CoinBalance.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {Token.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {TokenInstance.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {ContractCode.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {TokenBalance.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {TokenUpdater.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {ReplacedTransaction.Supervisor, [[memory_monitor: memory_monitor]]},

      # Out-of-band fetchers
      {CoinBalanceOnDemand.Supervisor, [json_rpc_named_arguments]},
      {EmptyBlocksSanitizer.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments]]},
      {TokenTotalSupplyOnDemand.Supervisor, [json_rpc_named_arguments]},
      {PendingTransactionsSanitizer, [[json_rpc_named_arguments: json_rpc_named_arguments]]},

      # Temporary workers
      {UncatalogedTokenTransfers.Supervisor, [[]]},
      {UnclesWithoutIndex.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {BlocksTransactionsMismatch.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {PendingOpsCleaner, [[], []]},

      # Celo
      {CeloAccount.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloValidator.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloValidatorGroup.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloValidatorHistory.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloElectionRewards.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloEpochRewards.Supervisor,
       [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloUnlocked.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloVoters.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
      {CeloMaterializedViewRefresh, [[], []]},
      {InternalTransactionCache, [[], []]}
    ]

    fetchers_with_bridged_tokens =
      if Chain.bridged_tokens_enabled?() do
        fetchers_with_omni_status = [{SetOmniBridgedMetadataForTokens, [[], []]} | basic_fetchers]
        [{CalcLpTokensTotalLiqudity, [[], []]} | fetchers_with_omni_status]
      else
        basic_fetchers
      end

    amb_bridge_mediators = Application.get_env(:block_scout_web, :amb_bridge_mediators)

    fetchers_with_amb_bridge_mediators =
      if amb_bridge_mediators && amb_bridge_mediators !== "" do
        [{SetAmbBridgedMetadataForTokens, [[], []]} | fetchers_with_bridged_tokens]
      else
        fetchers_with_bridged_tokens
      end

    metrics_enabled = Application.get_env(:indexer, :metrics_enabled)

    fetchers_with_metrics =
      if metrics_enabled do
        [{MetricsCron, [[]]} | fetchers_with_amb_bridge_mediators]
      else
        fetchers_with_amb_bridge_mediators
      end

    Supervisor.init(
      fetchers_with_metrics,
      strategy: :one_for_one
    )
  end
end
