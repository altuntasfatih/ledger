defmodule LedgerTest.Factory do
  @moduledoc """
  Test factory for generating unique IDs for tests.

  Uses sequences to ensure unique IDs across test runs within a session.
  Note: TigerBeetle persists data, so tests should use fresh database instances.
  """

  use ExMachina

  @doc "Generates a unique transaction ID starting from 100"
  @spec transaction_id_sequence() :: integer()
  def transaction_id_sequence, do: sequence(:transaction_id, &(&1 + 100))

  @doc "Generates a unique account ID starting from 10,000"
  @spec account_id_sequence() :: integer()
  def account_id_sequence, do: sequence(:account_id, &(&1 + 10_000))

  @doc "Generates a unique system account ID starting from 1"
  @spec system_account_id_sequence() :: integer()
  def system_account_id_sequence, do: sequence(:system_account_id, &(&1 + 1))

  # Note: Account IDs 0-100 are reserved for system accounts
end
