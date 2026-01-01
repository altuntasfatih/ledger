defmodule Ledger.Wallet do
  @moduledoc """
  Wallet operations for user accounts.

  Handles creating user wallets, deposits, and withdrawals using
  double-entry bookkeeping with TigerBeetle.
  """

  alias Ledger.Codes.AccountCode
  alias Ledger.Codes.TransferCode
  alias Ledger.Tigerbeetle
  alias TigerBeetlex.ID

  @liability_account_flags %{
    debits_must_not_exceed_credits: true
  }

  # Type definitions
  @type account_id :: integer() | binary()
  @type amount :: pos_integer()

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Creates a new user wallet (liability account).

  ## Parameters
    - wallet_id: Unique identifier for the wallet
    - external_id: External reference (e.g., user ID), defaults to 0

  ## Returns
    - `:ok` on success
    - `{:error, reason}` on failure
  """
  @spec create(integer(), integer()) :: :ok | {:error, term()}
  def create(wallet_id, external_id \\ 0) when is_integer(wallet_id) do
    Tigerbeetle.create_account(
      wallet_id,
      default_ledger_id!(),
      AccountCode.user_liability(),
      @liability_account_flags,
      external_id
    )
  end

  @doc """
  Retrieves wallet information.

  ## Parameters
    - wallet_id: The wallet's account ID

  ## Returns
    - `{:ok, account}` with balance information
    - `{:error, :account_not_found}` if wallet doesn't exist
  """
  @spec get(integer()) :: {:ok, map()} | {:error, :account_not_found}
  def get(wallet_id) when is_integer(wallet_id) do
    user_liability_code = AccountCode.user_liability()

    case Tigerbeetle.lookup_account(wallet_id) do
      {:ok, %{code: ^user_liability_code} = account} ->
        {:ok, account}

      _ ->
        {:error, :account_not_found}
    end
  end

  @doc """
  Returns the available balance for a wallet.

  Balance = credits_posted - debits_posted (for liability accounts)

  ## Parameters
    - wallet_id: The wallet's account ID

  ## Returns
    - `{:ok, balance}` with the current balance
    - `{:error, :account_not_found}` if wallet doesn't exist
  """
  @spec get_balance(integer()) :: {:ok, non_neg_integer()} | {:error, :account_not_found}
  def get_balance(wallet_id) when is_integer(wallet_id) do
    case get(wallet_id) do
      {:ok, %{credits_posted: credits, debits_posted: debits}} ->
        {:ok, credits - debits}

      error ->
        error
    end
  end

  @doc """
  Deposits funds into a wallet.

  ## Parameters
    - transaction_id: Unique identifier for this deposit transaction
    - wallet_id: The wallet's account ID
    - amount: Amount to deposit (must be positive)

  ## Returns
    - `{:ok, transfer_id}` on success
    - `{:error, reason}` on failure
  """
  @spec deposit(integer(), integer(), amount()) :: {:ok, binary()} | {:error, term()}
  def deposit(transaction_id, wallet_id, amount)
      when is_integer(wallet_id) and is_integer(amount) and amount > 0 do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <- fetch_user_account(wallet_id),
         {:ok, %{id: cash_asset_id}} <- ensure_cash_asset_account(ledger) do
      transfer_id = <<transaction_id::128>>

      build_transfer(
        transfer_id,
        cash_asset_id,
        user_liability_id,
        ledger,
        TransferCode.deposit(),
        amount
      )
      |> execute_transfer(transfer_id)
    end
  end

  @doc """
  Withdraws funds from a wallet.

  ## Parameters
    - transaction_id: Unique identifier for this withdrawal transaction
    - wallet_id: The wallet's account ID
    - amount: Amount to withdraw (must be positive)

  ## Returns
    - `{:ok, transfer_id}` on success
    - `{:error, :not_enough_balance}` if insufficient funds
    - `{:error, reason}` on other failures
  """
  @spec withdraw(integer(), integer(), amount()) :: {:ok, binary()} | {:error, term()}
  def withdraw(transaction_id, wallet_id, amount)
      when is_integer(wallet_id) and is_integer(amount) and amount > 0 do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <- fetch_user_account(wallet_id),
         {:ok, %{id: cash_asset_id}} <- ensure_cash_asset_account(ledger) do
      transfer_id = <<transaction_id::128>>

      build_transfer(
        transfer_id,
        user_liability_id,
        cash_asset_id,
        ledger,
        TransferCode.withdrawal(),
        amount
      )
      |> execute_transfer(transfer_id)
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec fetch_user_account(integer()) :: {:ok, map()} | {:error, :account_not_found}
  defp fetch_user_account(wallet_id) do
    user_liability_code = AccountCode.user_liability()

    case Tigerbeetle.lookup_account(wallet_id) do
      {:ok, %{code: ^user_liability_code} = acc} -> {:ok, acc}
      _ -> {:error, :account_not_found}
    end
  end

  @spec ensure_cash_asset_account(integer()) :: {:ok, %{id: binary()}} | {:error, term()}
  defp ensure_cash_asset_account(ledger) do
    cash_id = cash_asset_account_id!()
    code = AccountCode.cash_asset()

    case Tigerbeetle.query_accounts(ledger, code, cash_id, 1) do
      {:ok, [acc]} ->
        {:ok, acc}

      {:error, :not_found} ->
        case Tigerbeetle.create_account(cash_id, ledger, code, %{}, cash_id) do
          :ok -> {:ok, %{id: ID.from_int(cash_id)}}
          {:error, _} = error -> error
        end
    end
  end

  @spec build_transfer(binary(), binary(), binary(), integer(), integer(), amount()) ::
          TigerBeetlex.Transfer.t()
  defp build_transfer(id, debit_account_id, credit_account_id, ledger, code, amount) do
    %TigerBeetlex.Transfer{
      id: id,
      debit_account_id: debit_account_id,
      credit_account_id: credit_account_id,
      ledger: ledger,
      code: code,
      amount: amount,
      flags: struct(TigerBeetlex.TransferFlags, %{})
    }
  end

  @spec execute_transfer(TigerBeetlex.Transfer.t(), binary()) ::
          {:ok, binary()} | {:error, term()}
  defp execute_transfer(transfer, transfer_id) do
    case Tigerbeetle.create_transfer(transfer) do
      :ok ->
        {:ok, transfer_id}

      {:error, [%TigerBeetlex.CreateTransfersResult{result: :exceeds_credits}]} ->
        {:error, :not_enough_balance}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Configuration
  # ============================================================================

  @spec cash_asset_account_id!() :: integer()
  defp cash_asset_account_id! do
    Application.fetch_env!(:ledger, :ledger_details)
    |> Keyword.fetch!(:cash_asset_account_id)
  end

  @spec default_ledger_id!() :: integer()
  defp default_ledger_id! do
    Application.fetch_env!(:ledger, :ledger_details)
    |> Keyword.fetch!(:default_casino_ledger_id)
  end
end
