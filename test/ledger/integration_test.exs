defmodule Ledger.IntegrationTest do
  @moduledoc """
  Integration tests covering complete user gameplay scenarios.

  These tests simulate realistic user journeys through the system,
  verifying that all operations work correctly together and that
  account balances remain consistent throughout.
  """

  use LedgerTest.DataCase, async: false

  alias Ledger.GamePlay
  alias Ledger.Wallet

  describe "complete user journey" do
    setup do
      {:ok,
       wallet_id: create_user_wallet(),
       game_1: account_id_sequence(),
       game_2: account_id_sequence(),
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
           game_1: game_id
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
    end

    test "multi-game session: bets across different games with mixed outcomes", %{
      wallet_id: wallet_id,
      game_1: game_1,
      game_2: game_2
    } do
      # === User deposits $500 ===
      deposit_to_wallet(wallet_id, 500)
      assert {:ok, 500} = Wallet.get_balance(wallet_id)

      # === User bets on two games simultaneously ===
      {:ok, bet_1} = GamePlay.bet(wallet_id, game_1, 100)
      {:ok, bet_2} = GamePlay.bet(wallet_id, game_2, 150)
      assert {:ok, 250} = Wallet.get_balance(wallet_id)

      # === Game 1: User wins $200 ===
      {:ok, _} = GamePlay.win(bet_1, 200)
      # Balance: 250 + 200 = 450
      assert {:ok, 450} = Wallet.get_balance(wallet_id)

      # === Game 2: User loses ===
      {:ok, _} = GamePlay.loss(bet_2)
      # Balance unchanged (bet was already deducted)
      assert {:ok, 450} = Wallet.get_balance(wallet_id)

      # === Verify game pools are settled ===
      # Game 1: bet credited then debited (win returned to user)
      assert {:ok, %{credits_posted: 100, debits_posted: 100}} =
               Tigerbeetle.lookup_account(game_1)

      # Game 2: bet credited then debited (loss went to platform)
      assert {:ok, %{credits_posted: 150, debits_posted: 150}} =
               Tigerbeetle.lookup_account(game_2)
    end

    test "high roller session: large bets and full withdrawal", %{
      wallet_id: wallet_id,
      game_1: game_id,
      cash_asset_id: cash_asset_id
    } do
      # === High roller deposits $10,000 ===
      deposit_to_wallet(wallet_id, 10_000)
      assert {:ok, 10_000} = Wallet.get_balance(wallet_id)

      # === Places max bet of $5,000 ===
      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 5_000)
      assert {:ok, 5_000} = Wallet.get_balance(wallet_id)

      # === Wins big: $15,000 (3x multiplier) ===
      {:ok, _} = GamePlay.win(bet_id, 15_000)
      # Balance: 5000 + 15000 = 20000
      assert {:ok, 20_000} = Wallet.get_balance(wallet_id)

      # === Withdraws everything ===
      {:ok, _} = Wallet.withdraw(transaction_id_sequence(), wallet_id, 20_000)
      assert {:ok, 0} = Wallet.get_balance(wallet_id)

      # === Verify final cash position ===
      # Cash in: 10,000 (deposit)
      # Cash out: 10,000 (win payout) + 20,000 (withdrawal)
      # This means platform lost 20,000 on this player
      assert {:ok, %{debits_posted: 20_000, credits_posted: 20_000}} =
               Tigerbeetle.lookup_account(cash_asset_id)
    end

    test "streak session: multiple consecutive bets on same game", %{
      wallet_id: wallet_id,
      game_1: game_id
    } do
      # === User deposits $300 ===
      deposit_to_wallet(wallet_id, 300)

      # === Bet 1: $50 → Lose ===
      {:ok, bet_1} = GamePlay.bet(wallet_id, game_id, 50)
      {:ok, _} = GamePlay.loss(bet_1)
      assert {:ok, 250} = Wallet.get_balance(wallet_id)

      # === Bet 2: $50 → Lose ===
      {:ok, bet_2} = GamePlay.bet(wallet_id, game_id, 50)
      {:ok, _} = GamePlay.loss(bet_2)
      assert {:ok, 200} = Wallet.get_balance(wallet_id)

      # === Bet 3: $100 → Win $250 ===
      {:ok, bet_3} = GamePlay.bet(wallet_id, game_id, 100)
      {:ok, _} = GamePlay.win(bet_3, 250)
      # Balance: 100 (remaining) + 250 (win) = 350
      assert {:ok, 350} = Wallet.get_balance(wallet_id)

      # === User ends with profit despite 2 losses ===
      # Started with 300, now has 350 = $50 profit

      # === Verify game pool is fully settled ===
      # Total credits: 50 + 50 + 100 = 200
      # Total debits: 50 (loss to platform) + 50 (loss to platform) + 100 (win to user) = 200
      assert {:ok, %{credits_posted: 200, debits_posted: 200}} =
               Tigerbeetle.lookup_account(game_id)
    end
  end

  describe "edge cases" do
    setup do
      {:ok,
       wallet_id: create_user_wallet(),
       game_id: account_id_sequence(),
       cash_asset_id: setup_cash_asset_account()}
    end

    test "bet exactly the full balance", %{wallet_id: wallet_id, game_id: game_id} do
      deposit_to_wallet(wallet_id, 100)

      # Bet entire balance
      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 100)
      assert {:ok, 0} = Wallet.get_balance(wallet_id)

      # Win it back
      {:ok, _} = GamePlay.win(bet_id, 100)
      assert {:ok, 100} = Wallet.get_balance(wallet_id)
    end

    test "win exactly the bet amount (break even)", %{wallet_id: wallet_id, game_id: game_id} do
      deposit_to_wallet(wallet_id, 100)

      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 50)
      assert {:ok, 50} = Wallet.get_balance(wallet_id)

      # Win exactly the bet amount (no profit, no loss)
      {:ok, _} = GamePlay.win(bet_id, 50)
      assert {:ok, 100} = Wallet.get_balance(wallet_id)
    end

    test "cannot withdraw more than balance after losses", %{
      wallet_id: wallet_id,
      game_id: game_id
    } do
      deposit_to_wallet(wallet_id, 100)

      # Bet and lose
      {:ok, bet_id} = GamePlay.bet(wallet_id, game_id, 80)
      {:ok, _} = GamePlay.loss(bet_id)
      assert {:ok, 20} = Wallet.get_balance(wallet_id)

      # Try to withdraw original deposit amount
      assert {:error, :not_enough_balance} =
               Wallet.withdraw(transaction_id_sequence(), wallet_id, 100)

      # Can only withdraw remaining balance
      {:ok, _} = Wallet.withdraw(transaction_id_sequence(), wallet_id, 20)
      assert {:ok, 0} = Wallet.get_balance(wallet_id)
    end
  end
end
