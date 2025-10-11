defmodule Ledger.GamePlay do
  @moduledoc """
  Game play operations for betting, winning, and losing.

  Handles all game-related financial operations using double-entry
  bookkeeping with TigerBeetle.
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
  @type transfer_id :: integer() | binary()
  @type amount :: pos_integer()

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Places a bet on a game.

  Transfers funds from user's wallet to the game's bet pool.

  ## Parameters
    - user_account_id: The user's wallet account ID
    - game_id: The game's identifier (used as account ID for bet pool)
    - amount: Bet amount (must be positive)

  ## Returns
    - `{:ok, bet_id}` on success
    - `{:error, :not_enough_balance}` if insufficient funds
    - `{:error, reason}` on other failures
  """
  @spec bet(account_id(), integer(), amount()) :: {:ok, binary()} | {:error, term()}
  def bet(user_account_id, game_id, amount) when is_integer(amount) and amount > 0 do
    with {:ok, %{id: user_liability_id, ledger: ledger}} <- fetch_user_account(user_account_id),
         {:ok, %{id: game_pool_id}} <- ensure_game_pool_account(game_id, ledger) do
      bet_id = ID.generate()

      build_transfer(
        bet_id,
        user_liability_id,
        game_pool_id,
        ledger,
        TransferCode.bet(),
        amount
      )
      |> execute_transfer(bet_id)
    end
  end

  @doc """
  Processes a win on a game bet.

  Returns the original bet amount from the game pool to the user,
  plus pays additional winnings from the cash asset account.

  ## Parameters
    - bet_id: The original bet's transfer ID
    - win_amount: Total amount won (must be >= bet amount)

  ## Returns
    - `{:ok, [transfer_id1, transfer_id2]}` on success
    - `{:error, reason}` on failure
  """
  @spec win(transfer_id(), amount()) :: {:ok, [binary()]} | {:error, term()}
  def win(bet_id, win_amount) when is_integer(win_amount) and win_amount > 0 do
    with {:ok, bet_transfer} <- fetch_bet_transfer(bet_id),
         {:ok, %{id: cash_asset_id}} <- fetch_cash_asset_account() do
      %{
        credit_account_id: game_pool_id,
        debit_account_id: user_liability_id,
        ledger: ledger,
        amount: bet_amount
      } = bet_transfer

      transfer_one_id = ID.generate()
      transfer_two_id = ID.generate()

      # Return bet amount from game pool to user
      transfer_one =
        build_transfer(
          transfer_one_id,
          game_pool_id,
          user_liability_id,
          ledger,
          TransferCode.win(),
          bet_amount
        )

      # Pay additional winnings from cash asset to user
      payout_amount = win_amount - bet_amount

      transfer_two =
        build_transfer(
          transfer_two_id,
          cash_asset_id,
          user_liability_id,
          ledger,
          TransferCode.win(),
          payout_amount
        )

      case Tigerbeetle.create_transfers([transfer_one, transfer_two]) do
        :ok -> {:ok, [transfer_one_id, transfer_two_id]}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Processes a loss on a game bet.

  Transfers the bet amount from the game pool to the platform's cash asset.

  ## Parameters
    - bet_id: The original bet's transfer ID

  ## Returns
    - `{:ok, transfer_id}` on success
    - `{:error, reason}` on failure
  """
  @spec loss(transfer_id()) :: {:ok, binary()} | {:error, term()}
  def loss(bet_id) do
    with {:ok, bet_transfer} <- fetch_bet_transfer(bet_id),
         {:ok, %{id: cash_asset_id}} <- fetch_cash_asset_account() do
      %{
        credit_account_id: game_pool_id,
        ledger: ledger,
        amount: bet_amount
      } = bet_transfer

      transfer_id = ID.generate()

      # Transfer bet amount from game pool to cash asset (platform profit)
      build_transfer(
        transfer_id,
        game_pool_id,
        cash_asset_id,
        ledger,
        TransferCode.loss(),
        bet_amount
      )
      |> execute_transfer(transfer_id)
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec fetch_user_account(account_id()) :: {:ok, map()} | {:error, :account_not_found}
  defp fetch_user_account(account_id) do
    user_liability_code = AccountCode.user_liability()

    case Tigerbeetle.lookup_account(account_id) do
      {:ok, %{code: ^user_liability_code} = acc} -> {:ok, acc}
      _ -> {:error, :account_not_found}
    end
  end

  @spec fetch_bet_transfer(transfer_id()) :: {:ok, map()} | {:error, :transfer_not_found}
  defp fetch_bet_transfer(bet_id) do
    bet_code = TransferCode.bet()

    case Tigerbeetle.lookup_transfers([bet_id]) do
      {:ok, [%{code: ^bet_code} = transfer]} -> {:ok, transfer}
      _ -> {:error, :transfer_not_found}
    end
  end

  @spec fetch_cash_asset_account() :: {:ok, map()} | {:error, :account_not_found}
  defp fetch_cash_asset_account do
    cash_asset_code = AccountCode.cash_asset()

    case Tigerbeetle.lookup_account(cash_asset_account_id!()) do
      {:ok, %{code: ^cash_asset_code} = acc} -> {:ok, acc}
      _ -> {:error, :account_not_found}
    end
  end

  @spec ensure_game_pool_account(integer(), integer()) ::
          {:ok, %{id: binary()}} | {:error, term()}
  defp ensure_game_pool_account(game_id, ledger) do
    code = AccountCode.game_bet_pool()

    case Tigerbeetle.query_accounts(ledger, code, game_id, 1) do
      {:ok, [acc]} ->
        {:ok, acc}

      {:error, :not_found} ->
        case Tigerbeetle.create_account(game_id, ledger, code, @liability_account_flags, game_id) do
          :ok -> {:ok, %{id: ID.from_int(game_id)}}
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
end
