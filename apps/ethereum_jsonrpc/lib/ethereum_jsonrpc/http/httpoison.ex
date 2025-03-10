defmodule EthereumJSONRPC.HTTP.HTTPoison do
  @moduledoc """
  Uses `HTTPoison` for `EthereumJSONRPC.HTTP`
  """

  alias EthereumJSONRPC.HTTP
  alias HTTP.RpcResponseEts

  require UUID

  @behaviour HTTP

  @impl HTTP
  def json_rpc(url, json, options, method) when is_binary(url) and is_list(options) do
    id = UUID.uuid4()
    RpcResponseEts.put(id, %{:method => method, :start => :os.system_time(:millisecond)})

    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}], options) do
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}} ->
        RpcResponseEts.put(id, %{:finish => :os.system_time(:millisecond), :status_code => status_code})
        {:ok, %{body: body, status_code: status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        RpcResponseEts.delete(id)
        {:error, reason}
    end
  end

  def json_rpc(url, _json, _options, _method) when is_nil(url), do: {:error, "URL is nil"}
end
