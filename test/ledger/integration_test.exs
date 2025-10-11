defmodule Ledger.IntegrationTest do
  @moduledoc """
  Integration tests covering complete user gameplay scenarios.

  """

  use LedgerTest.DataCase, async: false

  alias Ledger.GamePlay
  alias Ledger.Wallet

  describe "complete user journey" do
    setup do
      {:ok,
       wallet_id: create_user_wallet(),
       game_1: account_id_sequence(),
       cash_asset_id: setup_cash_asset_account()}
    end

    test "winning session: deposit → bet → win → withdraw profits", %{
      wallet_id: wallet_id,
      game_1: game_id,
      cash_asset_id: cash_asset_id
    } do
      # === User deposits $1000 ===
      deposit_to_wallet(wallet_id, 1000)
      assert {:ok, 1000} = Wallet.get_balance(wallet_id)

      # === User bets $200 on a game ===
      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 200)
      assert {:ok, 800} = Wallet.get_balance(wallet_id)

      # === User wins $500 (2.5x their bet) ===
      {:ok, _} = GamePlay.win(bet_id, 500)

      # Balance should be: 800 (after bet) + 500 (winnings) = 1300
      assert {:ok, 1300} = Wallet.get_balance(wallet_id)

      # === User withdraws their profit ($300) ===
      {:ok, _} = Wallet.withdraw(transaction_id_sequence(), wallet_id, 300)
      assert {:ok, 1000} = Wallet.get_balance(wallet_id)

      # === Verify cash asset account is balanced ===
      # Cash received: 1000 (deposit)
      # Cash paid out: 300 (win payout = 500 - 200 bet) + 300 (withdrawal)
      # Net debits: 1000, Net credits: 600
      assert {:ok, %{debits_posted: 1300, credits_posted: 300}} =
               Tigerbeetle.lookup_account(cash_asset_id)
    end

    test "losing session: deposit → bet → lose → insufficient funds → deposit more → bet again",
         %{
           wallet_id: wallet_id,
           game_1: game_id,
           cash_asset_id: cash_asset_id
         } do
      # === User deposits $100 ===
      deposit_to_wallet(wallet_id, 100)
      assert {:ok, 100} = Wallet.get_balance(wallet_id)

      # === User bets $80 ===
      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 80)
      assert {:ok, 20} = Wallet.get_balance(wallet_id)

      # === User loses the bet ===
      {:ok, _} = GamePlay.loss(bet_id)

      # Balance stays at 20 (the bet was already deducted)
      assert {:ok, 20} = Wallet.get_balance(wallet_id)

      # === User tries to bet $50 but only has $20 ===
      assert {:error, :not_enough_balance} = GamePlay.bet(wallet_id, game_id, 50)

      # Balance unchanged
      assert {:ok, 20} = Wallet.get_balance(wallet_id)

      # === User deposits another $100 ===
      deposit_to_wallet(wallet_id, 100)
      assert {:ok, 120} = Wallet.get_balance(wallet_id)

      # === User can now bet $50 ===
      {:ok, _new_bet_id} = GamePlay.bet(wallet_id, game_id, 50)
      assert {:ok, 70} = Wallet.get_balance(wallet_id)

      # === Verify cash asset account received the lost bet ===
      # Cash received: 100 (first deposit) + 80 (lost bet) + 100 (second deposit)
      # Net debits: 200 (deposits), Net credits: 80 (lost bet revenue)
      assert {:ok, %{debits_posted: 200, credits_posted: 80}} =
               Tigerbeetle.lookup_account(cash_asset_id)
    end
  end
end
