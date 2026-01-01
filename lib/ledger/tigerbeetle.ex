defmodule Ledger.Tigerbeetle do
  @moduledoc """
  Low-level wrapper around TigerBeetlex for account and transfer operations.

  This module provides a simplified interface to TigerBeetle, handling
  connection management and result normalization.
  """

  alias TigerBeetlex.ID

  # Type definitions
  @type account_id :: integer() | binary()
  @type transfer_id :: integer() | binary()

  # ============================================================================
  # Account Operations
  # ============================================================================

  @doc """
  Creates an account in TigerBeetle.

  ## Parameters
    - id: Account identifier (integer)
    - ledger: Ledger ID
    - code: Account type code
    - flags: Account flags map (optional)
    - user_data_128: Custom user data (optional)
  """
  @spec create_account(integer(), integer(), integer(), map(), integer()) ::
          :ok | {:error, term()}
  def create_account(id, ledger, code, flags \\ %{}, user_data_128 \\ 0) do
    account = %TigerBeetlex.Account{
      id: ID.from_int(id),
      ledger: ledger,
      code: code,
      user_data_128: <<user_data_128::128>>,
      flags: struct(TigerBeetlex.AccountFlags, flags)
    }

    case TigerBeetlex.Connection.create_accounts(connection_name!(), [account]) do
      {:ok, stream} ->
        case Enum.to_list(stream) do
          [] -> :ok
          errors -> {:error, errors}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Looks up an account by ID.

  ## Parameters
    - id: Account identifier (integer or binary)

  ## Returns
    - `{:ok, account}` if found
    - `{:error, :account_not_found}` if not found
  """
  @spec lookup_account(account_id()) ::
          {:ok, TigerBeetlex.Account.t()} | {:error, :account_not_found}
  def lookup_account(id) when is_integer(id), do: do_lookup_account(ID.from_int(id))
  def lookup_account(id) when is_binary(id), do: do_lookup_account(id)

  @spec do_lookup_account(binary()) ::
          {:ok, TigerBeetlex.Account.t()} | {:error, :account_not_found}
  defp do_lookup_account(id) do
    case TigerBeetlex.Connection.lookup_accounts(connection_name!(), [id]) do
      {:ok, stream} ->
        case Enum.to_list(stream) do
          [%TigerBeetlex.Account{} = account] -> {:ok, account}
          _ -> {:error, :account_not_found}
        end

      {:error, _} ->
        {:error, :account_not_found}
    end
  end

  @doc """
  Queries accounts by ledger, code, and user_data_128.

  ## Parameters
    - ledger: Ledger ID to filter by
    - code: Account code to filter by
    - user_data_128: User data to filter by
    - limit: Maximum number of results (default: 100)

  ## Returns
    - `{:ok, accounts}` if found
    - `{:error, :not_found}` if no matches
  """
  @spec query_accounts(integer(), integer(), integer(), pos_integer()) ::
          {:ok, [TigerBeetlex.Account.t()]} | {:error, :not_found}
  def query_accounts(ledger, code, user_data_128, limit \\ 100) do
    query_filter = %TigerBeetlex.QueryFilter{
      ledger: ledger,
      code: code,
      user_data_128: <<user_data_128::128>>,
      limit: limit
    }

    case TigerBeetlex.Connection.query_accounts(connection_name!(), query_filter) do
      {:ok, stream} ->
        case Enum.to_list(stream) do
          [] -> {:error, :not_found}
          accounts -> {:ok, accounts}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  # ============================================================================
  # Transfer Operations
  # ============================================================================

  @doc """
  Creates a single transfer.
  """
  @spec create_transfer(TigerBeetlex.Transfer.t()) :: :ok | {:error, term()}
  def create_transfer(transfer), do: create_transfers([transfer])

  @doc """
  Creates multiple transfers atomically.

  ## Parameters
    - transfers: List of transfer structs

  ## Returns
    - `:ok` on success
    - `{:error, errors}` on failure
  """
  @spec create_transfers([TigerBeetlex.Transfer.t()]) :: :ok | {:error, term()}
  def create_transfers(transfers) when is_list(transfers) do
    case TigerBeetlex.Connection.create_transfers(connection_name!(), transfers) do
      {:ok, []} -> :ok
      {:ok, errors} -> {:error, errors}
      {:error, _} = error -> error
    end
  end

  @doc """
  Looks up transfers by their IDs.

  ## Parameters
    - ids: List of transfer IDs (integers or binaries)

  ## Returns
    - `{:ok, transfers}` if found
    - `{:error, :transfers_not_found}` if none found
  """
  @spec lookup_transfers([transfer_id()]) ::
          {:ok, [TigerBeetlex.Transfer.t()]} | {:error, :transfers_not_found}
  def lookup_transfers(ids) do
    normalized_ids =
      Enum.map(ids, fn
        id when is_integer(id) -> <<id::128>>
        id when is_binary(id) -> id
      end)

    case TigerBeetlex.Connection.lookup_transfers(connection_name!(), normalized_ids) do
      {:ok, transfers} when transfers != [] -> {:ok, transfers}
      {:ok, []} -> {:error, :transfers_not_found}
      {:error, _} -> {:error, :transfers_not_found}
    end
  end

  # ============================================================================
  # Health Check
  # ============================================================================

  @doc """
  Performs a health check by querying TigerBeetle.

  ## Returns
    - `{:ok, result}` if healthy
    - `{:error, reason}` if unhealthy
  """
  @spec health_check() :: {:ok, list()} | {:error, String.t()}
  def health_check do
    query_filter = %TigerBeetlex.QueryFilter{limit: 1}

    case TigerBeetlex.Connection.query_accounts(connection_name!(), query_filter) do
      {:ok, stream} -> {:ok, Enum.to_list(stream)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec connection_name!() :: atom()
  defp connection_name! do
    Application.fetch_env!(:ledger, :tigerbeetlex)
    |> Keyword.fetch!(:connection_name)
  end
end
