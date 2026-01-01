defmodule Ledger.GamePlayTest do
  use LedgerTest.DataCase, async: false

  describe "bet/4" do
    setup do
      _ = set_new_cash_asset_account()
      game_id = account_id_sequence()

      {:ok, user_account_id: create_user_account(), game_id: game_id}
    end

    test "it should bet on a game", %{
      user_account_id: user_account_id,
      game_id: game_id
    } do
      # given
      initial_balance = 100
      bet_amount = 10
      deposit_to_user_account(user_account_id, initial_balance)

      # when
      assert {:ok, _bet_id} = GamePlay.bet(user_account_id, game_id, bet_amount)

      # then
      assert {:ok,
              %{
                credits_posted: ^initial_balance,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(user_account_id)

      assert {:ok,
              %{
                debits_posted: 0,
                credits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_id)
    end

    test "it should return an error if the user does not have enough balance", %{
      user_account_id: user_account_id,
      game_id: game_id
    } do
      # given
      bet_amount = 1000

      # when
      assert {:error, :not_enough_balance} =
               GamePlay.bet(user_account_id, game_id, bet_amount)
    end
  end

  describe "win/4" do
    setup do
      {:ok,
       user_account_id: create_user_account(),
       game_account_id: account_id_sequence(),
       cash_asset_account_id: set_new_cash_asset_account()}
    end

    test "it should win on a game", %{
      user_account_id: user_account_id,
      game_account_id: game_account_id,
      cash_asset_account_id: cash_asset_account_id
    } do
      # given
      initial_balance = 100
      bet_amount = 20
      win_amount = 50
      deposit_to_user_account(user_account_id, initial_balance)
      bet_id = bet_on_game(user_account_id, game_account_id, bet_amount)

      # when
      assert :ok = GamePlay.win(bet_id, win_amount)

      # then - user receives full win amount
      final_user_credits = initial_balance + win_amount
      assert {:ok,
              %{
                credits_posted: ^final_user_credits,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(user_account_id)

      # cash asset: debited from deposit, debited again to pay winnings
      win_payout = win_amount - bet_amount
      total_cash_debits = initial_balance + win_payout

      assert {:ok,
              %{
                debits_posted: ^total_cash_debits,
                credits_posted: 0
              }} = Tigerbeetle.lookup_account(cash_asset_account_id)

      # game pool: bet was credited, then debited back to user
      assert {:ok,
              %{
                credits_posted: ^bet_amount,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_account_id)
    end
  end

  describe "loss/1" do
    setup do
      {:ok,
       user_account_id: create_user_account(),
       game_account_id: account_id_sequence(),
       cash_asset_account_id: set_new_cash_asset_account()}
    end

    test "it should process a loss - bet amount goes to platform", %{
      user_account_id: user_account_id,
      game_account_id: game_account_id,
      cash_asset_account_id: cash_asset_account_id
    } do
      # given
      initial_balance = 100
      bet_amount = 30
      deposit_to_user_account(user_account_id, initial_balance)
      bet_id = bet_on_game(user_account_id, game_account_id, bet_amount)

      # when - user loses the bet
      assert :ok = GamePlay.loss(bet_id)

      # then - user balance remains debited (they lost the bet)
      assert {:ok,
              %{
                credits_posted: ^initial_balance,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(user_account_id)

      # game pool is now empty (bet amount moved out)
      assert {:ok,
              %{
                credits_posted: ^bet_amount,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_account_id)

      # cash asset received the bet amount (platform profit)
      assert {:ok,
              %{
                debits_posted: ^initial_balance,
                credits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(cash_asset_account_id)
    end
  end
end
