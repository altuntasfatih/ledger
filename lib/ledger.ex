defmodule Ledger do
  @moduledoc """
  Ledger - A double-entry bookkeeping system using TigerBeetle.

  This module provides the main public API for the ledger system.
  It delegates to specialized modules for specific operations:

    * `Ledger.Wallet` - User wallet operations (create, deposit, withdraw)
    * `Ledger.GamePlay` - Game betting operations (bet, win, loss)
    * `Ledger.Tigerbeetle` - Low-level TigerBeetle operations
    * `Ledger.Codes.AccountCode` - Account type codes
    * `Ledger.Codes.TransferCode` - Transfer type codes

  ## Example

      # Create a wallet for a user
      :ok = Ledger.Wallet.create(user_id)

      # Deposit funds
      {:ok, _transfer_id} = Ledger.Wallet.deposit(tx_id, user_id, 1000)

      # Place a bet
      {:ok, bet_id} = Ledger.GamePlay.bet(user_id, game_id, 100)

      # Process win
      {:ok, _transfer_ids} = Ledger.GamePlay.win(bet_id, 200)

  """

  # Re-export commonly used modules for convenience
  defdelegate create_wallet(wallet_id, external_id \\ 0), to: Ledger.Wallet, as: :create
  defdelegate get_wallet(wallet_id), to: Ledger.Wallet, as: :get
  defdelegate get_balance(wallet_id), to: Ledger.Wallet, as: :get_balance
  defdelegate deposit(tx_id, wallet_id, amount), to: Ledger.Wallet
  defdelegate withdraw(tx_id, wallet_id, amount), to: Ledger.Wallet

  defdelegate bet(user_id, game_id, amount), to: Ledger.GamePlay
  defdelegate win(bet_id, win_amount), to: Ledger.GamePlay
  defdelegate loss(bet_id), to: Ledger.GamePlay

  defdelegate health_check(), to: Ledger.Tigerbeetle
end
