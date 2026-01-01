defmodule Ledger.GamePlayTest do
  use LedgerTest.DataCase, async: false

  alias Ledger.GamePlay

  describe "bet/3" do
    setup do
      _ = setup_cash_asset_account()
      game_id = account_id_sequence()

      {:ok, wallet_id: create_user_wallet(), game_id: game_id}
    end

    test "places a bet on a game", %{wallet_id: wallet_id, game_id: game_id} do
      # given
      initial_balance = 100
      bet_amount = 10
      deposit_to_wallet(wallet_id, initial_balance)

      # when
      assert {:ok, _bet_id} = GamePlay.bet(wallet_id, game_id, bet_amount)

      # then - user account debited
      assert {:ok,
              %{
                credits_posted: ^initial_balance,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(wallet_id)

      # game pool credited
      assert {:ok,
              %{
                debits_posted: 0,
                credits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_id)
    end

    test "returns error when user has insufficient balance", %{
      wallet_id: wallet_id,
      game_id: game_id
    } do
      # given - no deposit, balance is 0
      bet_amount = 1000

      # when/then
      assert {:error, :not_enough_balance} = GamePlay.bet(wallet_id, game_id, bet_amount)
    end
  end

  describe "win/2" do
    setup do
      {:ok,
       wallet_id: create_user_wallet(),
       game_id: account_id_sequence(),
       cash_asset_id: setup_cash_asset_account()}
    end

    test "processes a win - returns bet + pays winnings", %{
      wallet_id: wallet_id,
      game_id: game_id,
      cash_asset_id: cash_asset_id
    } do
      # given
      initial_balance = 100
      bet_amount = 20
      win_amount = 50
      deposit_to_wallet(wallet_id, initial_balance)
      bet_id = place_bet(wallet_id, game_id, bet_amount)

      # when
      assert {:ok, [_transfer_id1, _transfer_id2]} = GamePlay.win(bet_id, win_amount)

      # then - user receives full win amount
      final_user_credits = initial_balance + win_amount

      assert {:ok,
              %{
                credits_posted: ^final_user_credits,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(wallet_id)

      # cash asset: debited from deposit, debited again to pay winnings
      win_payout = win_amount - bet_amount
      total_cash_debits = initial_balance + win_payout

      assert {:ok,
              %{
                debits_posted: ^total_cash_debits,
                credits_posted: 0
              }} = Tigerbeetle.lookup_account(cash_asset_id)

      # game pool: bet was credited, then debited back to user
      assert {:ok,
              %{
                credits_posted: ^bet_amount,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_id)
    end
  end

  describe "loss/1" do
    setup do
      {:ok,
       wallet_id: create_user_wallet(),
       game_id: account_id_sequence(),
       cash_asset_id: setup_cash_asset_account()}
    end

    test "processes a loss - bet amount goes to platform", %{
      wallet_id: wallet_id,
      game_id: game_id,
      cash_asset_id: cash_asset_id
    } do
      # given
      initial_balance = 100
      bet_amount = 30
      deposit_to_wallet(wallet_id, initial_balance)
      bet_id = place_bet(wallet_id, game_id, bet_amount)

      # when
      assert {:ok, _transfer_id} = GamePlay.loss(bet_id)

      # then - user balance remains debited (they lost the bet)
      assert {:ok,
              %{
                credits_posted: ^initial_balance,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(wallet_id)

      # game pool is now empty (bet amount moved out)
      assert {:ok,
              %{
                credits_posted: ^bet_amount,
                debits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(game_id)

      # cash asset received the bet amount (platform profit)
      assert {:ok,
              %{
                debits_posted: ^initial_balance,
                credits_posted: ^bet_amount
              }} = Tigerbeetle.lookup_account(cash_asset_id)
    end
  end
end
