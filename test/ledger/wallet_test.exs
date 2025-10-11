defmodule Ledger.WalletTest do
  use LedgerTest.DataCase, async: false

  alias Ledger.Wallet

  describe "create/2" do
    setup do
      _ = setup_cash_asset_account()
      :ok
    end

    test "creates a user liability account" do
      # given
      wallet_id = account_id_sequence()

      # when
      assert :ok = Wallet.create(wallet_id, wallet_id)

      # then
      assert {:ok, account} = Tigerbeetle.lookup_account(wallet_id)
      assert account.id == ID.from_int(wallet_id)
      assert account.ledger == default_casino_ledger_id()
      assert account.code == user_liability_code()
      assert account.user_data_128 == <<wallet_id::128>>
    end
  end

  describe "get/1" do
    setup do
      _ = setup_cash_asset_account()
      {:ok, wallet_id: create_user_wallet()}
    end

    test "returns wallet account info", %{wallet_id: wallet_id} do
      assert {:ok, account} = Wallet.get(wallet_id)
      assert account.id == ID.from_int(wallet_id)
      assert account.code == user_liability_code()
    end

    test "returns error for non-existent wallet" do
      assert {:error, :account_not_found} = Wallet.get(999_999_999)
    end
  end

  describe "get_balance/1" do
    setup do
      _ = setup_cash_asset_account()
      {:ok, wallet_id: create_user_wallet()}
    end

    test "returns zero for new wallet", %{wallet_id: wallet_id} do
      assert {:ok, 0} = Wallet.get_balance(wallet_id)
    end

    test "returns correct balance after deposit", %{wallet_id: wallet_id} do
      deposit_to_wallet(wallet_id, 500)
      assert {:ok, 500} = Wallet.get_balance(wallet_id)
    end

    test "returns correct balance after deposit and withdrawal", %{wallet_id: wallet_id} do
      deposit_to_wallet(wallet_id, 500)
      {:ok, _} = Wallet.withdraw(transaction_id_sequence(), wallet_id, 200)
      assert {:ok, 300} = Wallet.get_balance(wallet_id)
    end
  end

  describe "deposit/3" do
    setup do
      {:ok, wallet_id: create_user_wallet(), cash_asset_id: setup_cash_asset_account()}
    end

    test "deposits funds to wallet", %{wallet_id: wallet_id, cash_asset_id: cash_asset_id} do
      # given
      amount = 100
      tx_id = transaction_id_sequence()

      # when
      assert {:ok, _transfer_id} = Wallet.deposit(tx_id, wallet_id, amount)

      # then - credit for liability account
      assert {:ok, %{credits_posted: ^amount}} = Tigerbeetle.lookup_account(wallet_id)

      # debit for asset account
      assert {:ok, %{debits_posted: ^amount}} = Tigerbeetle.lookup_account(cash_asset_id)
    end
  end

  describe "withdraw/3" do
    setup do
      {:ok, wallet_id: create_user_wallet(), cash_asset_id: setup_cash_asset_account()}
    end

    test "withdraws funds from wallet", %{wallet_id: wallet_id, cash_asset_id: cash_asset_id} do
      # given
      initial_deposit = 100
      deposit_to_wallet(wallet_id, initial_deposit)
      withdrawal_amount = 50

      # when
      assert {:ok, _transfer_id} =
               Wallet.withdraw(transaction_id_sequence(), wallet_id, withdrawal_amount)

      # then
      assert {:ok,
              %{
                credits_posted: ^initial_deposit,
                debits_posted: ^withdrawal_amount
              }} = Tigerbeetle.lookup_account(wallet_id)

      assert {:ok,
              %{
                debits_posted: ^initial_deposit,
                credits_posted: ^withdrawal_amount
              }} = Tigerbeetle.lookup_account(cash_asset_id)
    end

    test "returns error when withdrawing more than balance", %{wallet_id: wallet_id} do
      # given
      deposit_to_wallet(wallet_id, 100)

      # when/then
      assert {:error, :not_enough_balance} =
               Wallet.withdraw(transaction_id_sequence(), wallet_id, 150)
    end
  end
end
