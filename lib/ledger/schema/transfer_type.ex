defmodule Ledger.Schema.TransferType do
  @type transfer_type ::
          :deposit
          | :withdrawal
          | :bet
          | :win
          | :loss

  @code %{
    :deposit => 1,
    :withdrawal => 2,
    :bet => 3,
    :win => 4,
    :loss => 5
  }

  def deposit, do: @code[:deposit]
  def withdrawal, do: @code[:withdrawal]
  def bet, do: @code[:bet]
  def win, do: @code[:win]
  def loss, do: @code[:loss]
end
