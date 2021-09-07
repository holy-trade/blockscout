defmodule Mix.Tasks.AssembleRequests do
  use Mix.Task

  def run([]), do: IO.puts("Need some blocks to fetch transactions for")

  def run(args) do
    HTTPoison.start()

    {options, blocks, _} = OptionParser.parse(args, strict: [output: :string])
    blocks_request = blocks
             |> Enum.map(&(String.split(&1, ~r/[\s,]/)))
             |> List.flatten
             |> Enum.map(&String.to_integer/1)
             |> build_blocks_request()

    transaction_json =
      blocks_request
      |> send_request()
      |> extract_transactions()
      |> Enum.map(&build_transactions_request/1)

    if options[:output] do
      File.write(options[:output], transaction_json)
    end

    #send_internal_transaction_request(transaction_json)
  end

  def send_request(json) do
    url = System.get_env("ETHEREUM_JSONRPC_HTTP_URL", "")
    start_time = :os.system_time(:millisecond)
    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
        {:ok, %{body: body, status_code: status_code}}
      bad_response ->
        {:fail, bad_response, :os.system_time(:millisecond) - start_time}
    end
  end

  def extract_transactions({:ok, %{status_code: 200, body: transaction_body}}) do
    transaction_body
    |> Jason.decode!
    |> Enum.map(fn block_response ->
      result = block_response["result"]
      Enum.reduce(result["transactions"], [], fn t,acc ->
        [ %{block_number: hex_to_int(result["number"]), block_hash: result["hash"], index: t["transactionIndex"], transaction_hash: t["hash"]} | acc ]
      end)
      |> Enum.reverse
    end)
  end

  def hex_to_int("0x" <> str), do: String.to_integer(str, 16)

  def build_blocks_request(blocks) do
    blocks
    |> Enum.reduce({0,[]} , fn number, {id, requests} ->
      r = %{jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["0x"<> Integer.to_string(number, 16), true], id: id}
      {id + 1, [r | requests]}
    end)
    |> elem(1)
    |> Jason.encode!
  end

  @tracer_path "../../apps/ethereum_jsonrpc/priv/js/ethereum_jsonrpc/geth/debug_traceTransaction/tracer.js"
  @external_resource @tracer_path
  @tracer File.read!(@tracer_path)
  def build_transactions_request(transactions) do
    transactions
    |> Enum.reduce({0,[]} , fn %{transaction_hash: t}, {id, requests} ->
      r = %{jsonrpc: "2.0", method: "debug_traceTransaction", params: [t, %{tracer: @tracer, timeout: "100s"}], id: id}
      {id + 1, [r | requests]}
    end)
    |> elem(1)
    |> Jason.encode!

  end
end