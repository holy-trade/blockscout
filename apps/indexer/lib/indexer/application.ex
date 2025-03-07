defmodule Indexer.Application do
  @moduledoc """
  This is the `Application` module for `Indexer`.
  """

  use Application

  alias Indexer.{LoggerBackend, Memory, Prometheus}
  alias Prometheus.Setup

  @impl Application
  def start(_type, _args) do
    memory_monitor_options =
      case Application.get_env(:indexer, :memory_limit) do
        nil -> %{}
        integer when is_integer(integer) -> %{limit: integer}
      end

    memory_monitor_name = Memory.Monitor
    Setup.setup()

    base_children = [
      {Memory.Monitor, [memory_monitor_options, [name: memory_monitor_name]]},
      {Plug.Cowboy,
       scheme: :http, plug: Indexer.Stack, options: [port: Application.get_env(:indexer, :health_check_port)]}
    ]

    children =
      if Application.get_env(:indexer, Indexer.Supervisor)[:enabled] do
        Enum.reverse([{Indexer.Supervisor, [%{memory_monitor: memory_monitor_name}]} | base_children])
      else
        base_children
      end

    opts = [
      # If the `Memory.Monitor` dies, it needs all the `Shrinkable`s to re-register, so restart them.
      strategy: :rest_for_one,
      name: Indexer.Application
    ]

    Logger.add_backend(LoggerBackend)

    Supervisor.start_link(children, opts)
  end
end
