defmodule Ledger do
  alias Ledger.Schema.Account
  alias Ledger.Schema.TransferType
  alias TigerBeetlex.ID

  alias Ledger.Tigerbeetle

  @liability_account_flags %{
    debits_must_not_exceed_credits: true
  }

  # id -> use to identify account
  # code -> use to idetify account type
  # flags -> use to store additional information
  # external_id -> use to store additional information, could be user id, game id, etc.
  def create_user_account(account_id, external_id \\ 0) do
    Tigerbeetle.create_account(
      account_id,
      default_casino_ledger_id(),
      user_liability_code(),
      @liability_account_flags,
      external_id
    )
  end

  def deposit_to_user_account(deposit_id, user_account_id, amount) when amount > 0 do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <-
           fetch_account(user_account_id, user_liability_code()),
         {:ok, %{id: cash_asset_id}} <- ensure_cash_asset_account(ledger),
         {:ok, []} <-
           deposit(
             deposit_id,
             user_liability_id,
             cash_asset_id,
             ledger,
             amount
           ) do
      :ok
    end
  end

  def withdraw_from_user_account(withdrawal_id, user_account_id, amount) when amount > 0 do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <-
           fetch_account(user_account_id, user_liability_code()),
         {:ok, %{id: cash_asset_id}} <-
           ensure_cash_asset_account(ledger),
         {:ok, []} <-
           withdraw(
             withdrawal_id,
             user_liability_id,
             cash_asset_id,
             ledger,
             amount
           ) do
      :ok
    end
  end

  defp deposit(deposit_id, user_liability_id, cash_asset_id, ledger, amount)
       when amount > 0 and is_binary(user_liability_id) and
              is_binary(cash_asset_id) do
    %TigerBeetlex.Transfer{
      id: <<deposit_id::128>>,
      debit_account_id: cash_asset_id,
      credit_account_id: user_liability_id,
      ledger: ledger,
      code: TransferType.deposit(),
      amount: amount,
      flags: struct(TigerBeetlex.TransferFlags, %{})
    }
    |> Tigerbeetle.create_transfer()
  end

  defp withdraw(withdrawal_id, user_liability_id, cash_asset_id, ledger, amount)
       when amount > 0 and is_binary(user_liability_id) and
              is_binary(cash_asset_id) do
    %TigerBeetlex.Transfer{
      id: <<withdrawal_id::128>>,
      debit_account_id: user_liability_id,
      credit_account_id: cash_asset_id,
      ledger: ledger,
      code: TransferType.withdrawal(),
      amount: amount,
      flags: struct(TigerBeetlex.TransferFlags, %{})
    }
    |> Tigerbeetle.create_transfer()
  end

  def fetch_account(account_id, code) do
    case Tigerbeetle.lookup_account(account_id) do
      {:ok, %{code: ^code} = acc} -> {:ok, acc}
      _ -> {:error, :account_not_found}
    end
  end

  def fetch_transfer(transfer_id, transfer_type) do
    case Tigerbeetle.lookup_transfers([transfer_id]) do
      {:ok, [%{code: ^transfer_type} = transfer]} -> {:ok, transfer}
      _ -> {:error, :transfer_not_found}
    end
  end

  def bet_on_game(user_account_id, game_account_id, amount) do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <-
           fetch_account(user_account_id, user_liability_code()),
         {:ok, %{id: game_bet_pool_liability_id}} <-
           ensure_game_bet_pool_liability_account(game_account_id, ledger) do
      bet(user_liability_id, game_bet_pool_liability_id, ledger, amount)
    end
  end

  defp bet(user_liability_id, game_bet_pool_liability_id, ledger, amount) do
    bet_id = ID.generate()

    %TigerBeetlex.Transfer{
      id: bet_id,
      debit_account_id: user_liability_id,
      credit_account_id: game_bet_pool_liability_id,
      ledger: ledger,
      code: TransferType.bet(),
      amount: amount,
      flags: struct(TigerBeetlex.TransferFlags, %{})
    }
    |> Tigerbeetle.create_transfer()
    |> then(fn
      {:error, [%TigerBeetlex.CreateTransfersResult{result: :exceeds_credits}]} ->
        {:error, :not_enough_balance}

      :ok ->
        {:ok, bet_id}
    end)
  end

  def win_on_game(bet_id, win_amount) do
    with {:ok,
          %{credit_account_id: game_bet_pool_liability_id, debit_account_id: user_liability_id} =
            bet_transfer} <-
           fetch_transfer(bet_id, TransferType.bet()) do
      with {:ok, %{id: cash_asset_id}} <-
             fetch_account(cash_asset_account_id(), Account.cash_asset_code()) do
        transfer_one = %TigerBeetlex.Transfer{
          id: ID.generate(),
          credit_account_id: user_liability_id,
          debit_account_id: game_bet_pool_liability_id,
          ledger: bet_transfer.ledger,
          code: TransferType.win(),
          amount: bet_transfer.amount,
          flags: struct(TigerBeetlex.TransferFlags, %{})
        }

        remaining_amount = win_amount - bet_transfer.amount

        transfer_two = %TigerBeetlex.Transfer{
          id: ID.generate(),
          credit_account_id: user_liability_id,
          debit_account_id: cash_asset_id,
          ledger: bet_transfer.ledger,
          code: TransferType.win(),
          amount: remaining_amount,
          flags: struct(TigerBeetlex.TransferFlags, %{})
        }

        [transfer_one, transfer_two]
        |> Tigerbeetle.create_transfers()
      end
    end
  end

  def loss_on_game(bet_id) do
    with {:ok,
          %{credit_account_id: game_bet_pool_liability_id, amount: bet_amount} = bet_transfer} <-
           fetch_transfer(bet_id, TransferType.bet()),
         {:ok, %{id: cash_asset_id}} <-
           fetch_account(cash_asset_account_id(), Account.cash_asset_code()) do
      # Transfer the bet amount from game pool to cash asset (platform keeps the money)
      %TigerBeetlex.Transfer{
        id: ID.generate(),
        debit_account_id: game_bet_pool_liability_id,
        credit_account_id: cash_asset_id,
        ledger: bet_transfer.ledger,
        code: TransferType.loss(),
        amount: bet_amount,
        flags: struct(TigerBeetlex.TransferFlags, %{})
      }
      |> Tigerbeetle.create_transfer()
    end
  end

  defp ensure_game_bet_pool_liability_account(game_id, ledger) do
    code = Account.game_bet_pool_liability_code()

    with {:error, :not_found} <- Tigerbeetle.query_accounts(ledger, code, game_id, 1),
         :ok <-
           Tigerbeetle.create_account(game_id, ledger, code, @liability_account_flags, game_id) do
      {:ok, %{id: ID.from_int(game_id)}}
    else
      {:ok, [acc]} -> {:ok, acc}
    end
  end

  defp ensure_cash_asset_account(ledger) do
    code = Account.cash_asset_code()
    cash_account_id = cash_asset_account_id()

    with {:error, :not_found} <- Tigerbeetle.query_accounts(ledger, code, cash_account_id, 1),
         :ok <-
           Tigerbeetle.create_account(cash_account_id, ledger, code, %{}, cash_account_id) do
      {:ok, %{id: ID.from_int(cash_account_id)}}
    else
      {:ok, [acc]} -> {:ok, acc}
    end
  end

  defp user_liability_code, do: Account.user_liability_code()

  defp cash_asset_account_id,
    do: Application.get_env(:ledger, :ledger_details)[:cash_asset_account_id]

  defp default_casino_ledger_id,
    do: Application.get_env(:ledger, :ledger_details)[:default_casino_ledger_id]
end
