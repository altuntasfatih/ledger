defmodule Ledger.Codes.AccountCode do
  @moduledoc """
  Defines account type codes for TigerBeetle ledger accounts.

  Each account type is identified by a unique integer code that is stored
  in TigerBeetle's `code` field for categorization and querying.
  """

  @type t ::
          :cash_asset
          | :game_bet_pool
          | :user_liability
          | :system_revenue_equity
          | :system_capital_equity

  @cash_asset 10
  @game_bet_pool 20
  @user_liability 30
  @system_revenue_equity 40
  @system_capital_equity 50

  @doc "Cash asset account code (platform's cash holdings)"
  @spec cash_asset() :: 10
  def cash_asset, do: @cash_asset

  @doc "Game bet pool liability account code (holds active bets)"
  @spec game_bet_pool() :: 20
  def game_bet_pool, do: @game_bet_pool

  @doc "User liability account code (user's balance)"
  @spec user_liability() :: 30
  def user_liability, do: @user_liability

  @doc "System revenue equity account code"
  @spec system_revenue_equity() :: 40
  def system_revenue_equity, do: @system_revenue_equity

  @doc "System capital equity account code"
  @spec system_capital_equity() :: 50
  def system_capital_equity, do: @system_capital_equity

  @doc "Returns all valid account codes"
  @spec all() :: [10 | 20 | 30 | 40 | 50]
  def all,
    do: [
      @cash_asset,
      @game_bet_pool,
      @user_liability,
      @system_revenue_equity,
      @system_capital_equity
    ]
end
