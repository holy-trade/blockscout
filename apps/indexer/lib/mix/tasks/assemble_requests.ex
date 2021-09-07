defmodule Mix.Tasks.AssembleRequests do
  use Mix.Task

  def run([]), do: IO.puts("Need some blocks to fetch transactions for")

  def run(args) do
    HTTPoison.start()

    blocks = args
             |> Enum.map(&(String.split(&1, ~r/[\s,]/)))
             |> List.flatten
             |> Enum.map(&String.to_integer/1)
             |> get_blocks_json

    url = System.get_env("ETHEREUM_JSONRPC_HTTP_URL", "")


    #get list of blocks
    #map to transactions
    #build json

    IO.inspect(blocks)
    send_request(url, blocks)
    |> IO.inspect()
  end

  def send_request(url, json) do
    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
        {:ok, %{body: body, status_code: status_code}}
    end
  end

  def get_blocks_json(blocks) do
    blocks
    |> Enum.reduce({0,[]} , fn number, {id, requests} ->
      r = %{jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["0x"<> Integer.to_string(number, 16), true], id: id}
      {id + 1, [r | requests]}
    end)
    |> elem(1)
    |> Jason.encode!
  end
end