defmodule Ledger.Application do
  @moduledoc """
  OTP Application for the Ledger system.

  Starts and supervises the TigerBeetlex connection.
  """

  use Application

  @impl true
  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    children = [
      {TigerBeetlex.Connection, tigerbeetle_config()}
    ]

    opts = [strategy: :one_for_one, name: Ledger.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @spec tigerbeetle_config() :: keyword()
  defp tigerbeetle_config do
    config = Application.fetch_env!(:ledger, :tigerbeetlex)

    [
      addresses: Keyword.fetch!(config, :addresses),
      cluster_id: config |> Keyword.fetch!(:cluster) |> TigerBeetlex.ID.from_int(),
      name: Keyword.fetch!(config, :connection_name)
    ]
  end
end
