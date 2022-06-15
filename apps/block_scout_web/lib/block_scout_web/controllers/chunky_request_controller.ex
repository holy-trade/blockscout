defmodule BlockScoutWeb.ChunkyRequestController do
  use BlockScoutWeb, :controller

  alias Explorer.Repo

  def index(conn, params) do
    {duration, _} = params["duration"] || "120" |> Integer.parse()
    query = "select clock_timestamp(), pg_sleep($1), clock_timestamp()"

    case params["async"] do
      nil ->
        result = Ecto.Adapters.SQL.query!(Repo, query, [duration])
        json(
          conn,
          %{result: inspect(result)} )
      _ ->

        task_pid = Task.Supervisor.async(Explorer.TaskSupervisor, fn ->
          Ecto.Adapters.SQL.query!(Repo, query, [duration])
        end)

        result = Task.await(task_pid)
          json(
            conn,
            %{result: inspect(result)} )
    end
  end
end