defmodule Ledger.Codes.TransferCode do
  @moduledoc """
  Defines transfer type codes for TigerBeetle ledger transfers.

  Each transfer type is identified by a unique integer code that is stored
  in TigerBeetle's `code` field for categorization and querying.
  """

  @type t ::
          :deposit
          | :withdrawal
          | :bet
          | :win
          | :loss

  @deposit 1
  @withdrawal 2
  @bet 3
  @win 4
  @loss 5

  @doc "Deposit transfer code (funds entering user account)"
  @spec deposit() :: 1
  def deposit, do: @deposit

  @doc "Withdrawal transfer code (funds leaving user account)"
  @spec withdrawal() :: 2
  def withdrawal, do: @withdrawal

  @doc "Bet transfer code (user placing a bet)"
  @spec bet() :: 3
  def bet, do: @bet

  @doc "Win transfer code (user receiving winnings)"
  @spec win() :: 4
  def win, do: @win

  @doc "Loss transfer code (bet amount going to platform)"
  @spec loss() :: 5
  def loss, do: @loss

  @doc "Returns all valid transfer codes"
  @spec all() :: [1 | 2 | 3 | 4 | 5]
  def all, do: [@deposit, @withdrawal, @bet, @win, @loss]
end
