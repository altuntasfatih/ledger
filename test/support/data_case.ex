defmodule LedgerTest.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  Provides test helpers for creating wallets, deposits, and bets.
  """

  use ExUnit.CaseTemplate

  alias Ledger.Codes.AccountCode

  using do
    quote do
      alias Ledger.Codes.AccountCode
      alias Ledger.Codes.TransferCode
      alias Ledger.GamePlay
      alias Ledger.Tigerbeetle
      alias Ledger.Wallet
      alias TigerBeetlex.ID

      import LedgerTest.DataCase
      import LedgerTest.Factory
    end
  end

  @doc "Creates a user wallet and returns the wallet ID"
  @spec create_user_wallet() :: integer()
  def create_user_wallet do
    wallet_id = LedgerTest.Factory.account_id_sequence()
    assert :ok = Ledger.Wallet.create(wallet_id, wallet_id)
    wallet_id
  end

  @doc "Deposits funds into a wallet"
  @spec deposit_to_wallet(integer(), pos_integer()) :: {:ok, binary()}
  def deposit_to_wallet(wallet_id, amount) do
    tx_id = LedgerTest.Factory.transaction_id_sequence()
    assert {:ok, transfer_id} = Ledger.Wallet.deposit(tx_id, wallet_id, amount)
    {:ok, transfer_id}
  end

  @doc "Places a bet and returns the bet ID"
  @spec place_bet(integer(), integer(), pos_integer()) :: binary()
  def place_bet(wallet_id, game_id, amount) do
    assert {:ok, bet_id} = Ledger.GamePlay.bet(wallet_id, game_id, amount)
    bet_id
  end

  @doc "Sets up a new cash asset account for test isolation"
  @spec setup_cash_asset_account() :: integer()
  def setup_cash_asset_account do
    cash_asset_id = LedgerTest.Factory.system_account_id_sequence()

    details =
      Application.get_env(:ledger, :ledger_details)
      |> Keyword.put(:cash_asset_account_id, cash_asset_id)

    :ok = Application.put_env(:ledger, :ledger_details, details)
    cash_asset_id
  end

  @doc "Returns the user liability account code"
  @spec user_liability_code() :: integer()
  def user_liability_code, do: AccountCode.user_liability()

  @doc "Returns the cash asset account code"
  @spec cash_asset_code() :: integer()
  def cash_asset_code, do: AccountCode.cash_asset()

  @doc "Returns the default casino ledger ID from config"
  @spec default_casino_ledger_id() :: integer()
  def default_casino_ledger_id do
    Application.get_env(:ledger, :ledger_details)[:default_casino_ledger_id]
  end

  # Legacy aliases for backward compatibility with existing tests
  def create_user_account, do: create_user_wallet()
  def deposit_to_user_account(wallet_id, amount), do: deposit_to_wallet(wallet_id, amount)
  def bet_on_game(wallet_id, game_id, amount), do: place_bet(wallet_id, game_id, amount)
  def set_new_cash_asset_account, do: setup_cash_asset_account()
end
