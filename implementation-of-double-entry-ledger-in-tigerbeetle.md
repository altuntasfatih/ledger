# Implementation of a Double-Entry Ledger in TigerBeetle

In the previous article, we explored the fundamentals of double-entry bookkeeping and walked through how a ledger system works with real examples.

Now, in this follow-up, we'll implement that ledger system using Elixir and TigerBeetle. As promised, this story will be more hands-on — expect plenty of code. 🚀

## Why TigerBeetle?

TigerBeetle is a purpose-built financial database designed for high-throughput and correctness. TigerBeetle comes with a pre-defined database schema — double-entry bookkeeping, which was explained in the previous post.

We decided to migrate from PostgreSQL to TigerBeetle after hitting scalability limits. (If you want a deeper dive into why TigerBeetle is better suited as a ledger database, you can check their documentation — but here we'll focus mainly on the implementation.)

## Install TigerBeetle

Let's install TigerBeetle on your machine:

```bash
# macOS
➜ curl -Lo tigerbeetle.zip https://mac.tigerbeetle.com
➜ unzip tigerbeetle.zip
➜ sudo mv tigerbeetle /usr/local/bin/
➜ tigerbeetle version
TigerBeetle version 0.16.66
```

A TigerBeetle replica stores everything in a single file (`0_0.tigerbeetle`).

The `--cluster`, `--replica`, and `--replica-count` flags define the cluster topology. For this tutorial, we'll use a single replica:

```bash
➜ tigerbeetle format --cluster=0 --replica=0 --replica-count=1 --development 0_0.tigerbeetle
2025-10-04 11:51:05.213Z info(main): 0: formatted: cluster=0 replica_count=1
```

Now let's start the replica:

```bash
➜ tigerbeetle start --addresses=3000 --development ./0_0.tigerbeetle
2025-10-04 11:51:31.355Z info(main): 0: cluster=0: listening on 127.0.0.1:3000
2025-10-04 11:51:31.355Z info(main): 0: started with extra verification checks
```

Now it's running and accepts connections on port 3000. Let's connect via REPL and play:

```bash
➜ tigerbeetle repl --cluster=0 --addresses=3000
```

```sql
create_accounts id=1 code=10 ledger=700, id=2 code=10 ledger=700;
create_transfers id=1 debit_account_id=1 credit_account_id=2 amount=10 ledger=700 code=10;
lookup_accounts id=1, id=2;
```

```json
{
  "id": "1",
  "ledger": "700",
  "code": "10",
  "debits_posted": "10",
  "credits_posted": "0"
}
{
  "id": "2",
  "ledger": "700",
  "code": "10",
  "debits_posted": "0",
  "credits_posted": "10"
}
```

As shown above, we created two accounts in the same ledger (required for transfers) and sent 10 units from account_1 to account_2.

Account 1 was debited, and Account 2 was credited — the essence of double-entry bookkeeping.

## Project Setup

Let's create a new Elixir project and add `tigerbeetlex`, the Elixir client. Its version should match what we installed in the previous step to avoid conflicts:

```elixir
# mix.exs
def deps do
  [
    {:tigerbeetlex, "~> 0.16.66"}
  ]
end
```

Configure the TigerBeetle connection:

```elixir
# config/dev.exs
config :ledger, :tigerbeetlex,
  connection_name: :tb,
  cluster: 0,
  addresses: ["127.0.0.1:3000"]

config :ledger, :ledger_details,
  cash_asset_account_id: 1,
  default_casino_ledger_id: 1
```

## Defining Our Schema

Before we dive into the implementation, let's define our account types and transfer types. In TigerBeetle, accounts have a `code` field that we use to identify the account type:

```elixir
# lib/ledger/schema/account.ex
defmodule Ledger.Schema.Account do
  @type account_type ::
          :cash_asset
          | :game_bet_pool
          | :user_liability
          | :system_revenue_equity
          | :system_capital_equity

  @code %{
    :cash_asset => 10,
    :game_bet_pool => 20,
    :user_liability => 30,
    :system_revenue_equity => 40,
    :system_capital_equity => 50
  }

  def cash_asset_code, do: @code[:cash_asset]
  def game_bet_pool_liability_code, do: @code[:game_bet_pool]
  def user_liability_code, do: @code[:user_liability]
  def system_revenue_equity_code, do: @code[:system_revenue_equity]
  def system_capital_equity_code, do: @code[:system_capital_equity]
end
```

Similarly, we define transfer types:

```elixir
# lib/ledger/schema/transfer_type.ex
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
```

## The TigerBeetle Wrapper

We create a thin wrapper around the TigerBeetle client to handle common operations:

```elixir
# lib/ledger/tigerbeetle.ex
defmodule Ledger.Tigerbeetle do
  alias TigerBeetlex.ID

  def create_account(id, ledger, code, flags \\ %{}, user_data_128 \\ 0) do
    accounts = [
      %TigerBeetlex.Account{
        id: ID.from_int(id),
        ledger: ledger,
        code: code,
        user_data_128: <<user_data_128::128>>,
        flags: struct(TigerBeetlex.AccountFlags, flags)
      }
    ]

    {:ok, stream} = TigerBeetlex.Connection.create_accounts(get_connection_name!(), accounts)

    case Enum.to_list(stream) do
      [] -> :ok
      reason -> {:error, reason}
    end
  end

  def create_transfer(t), do: create_transfers([t])

  def create_transfers(transfers) when is_list(transfers) do
    case TigerBeetlex.Connection.create_transfers(get_connection_name!(), transfers) do
      {:ok, []} -> :ok
      {:ok, error} -> {:error, error}
      err -> {:error, err}
    end
  end

  def lookup_account(id) when is_integer(id), do: lookup_accounts(ID.from_int(id))
  def lookup_account(id) when is_binary(id), do: lookup_accounts(id)

  defp lookup_accounts(id) do
    {:ok, stream} = TigerBeetlex.Connection.lookup_accounts(get_connection_name!(), [id])

    case Enum.to_list(stream) do
      [%TigerBeetlex.Account{} = account] -> {:ok, account}
      _ -> {:error, :account_not_found}
    end
  end

  def lookup_transfers(ids) do
    ids = Enum.map(ids, fn
      id when is_integer(id) -> <<id::128>>
      id -> id
    end)

    case TigerBeetlex.Connection.lookup_transfers(get_connection_name!(), ids) do
      {:ok, transfers} when transfers != [] -> {:ok, transfers}
      {:ok, []} -> {:error, :transfers_not_found}
    end
  end

  def query_accounts(ledger, code, user_data_128, limit \\ 100) do
    query_filter = %TigerBeetlex.QueryFilter{
      ledger: ledger,
      code: code,
      user_data_128: <<user_data_128::128>>,
      limit: limit
    }

    {:ok, stream} = TigerBeetlex.Connection.query_accounts(get_connection_name!(), query_filter)

    case Enum.to_list(stream) do
      [%TigerBeetlex.Account{}] = list -> {:ok, list}
      _ -> {:error, :not_found}
    end
  end

  defp get_connection_name!,
    do: Application.get_env(:ledger, :tigerbeetlex, []) |> Keyword.fetch!(:connection_name)
end
```

## The Core Ledger Module

Now for the heart of our implementation — the Ledger module that handles all financial operations:

### Creating User Accounts

User accounts are **liability accounts** — they represent money we owe to users. We set the `debits_must_not_exceed_credits` flag to prevent users from spending more than they have:

```elixir
@liability_account_flags %{
  debits_must_not_exceed_credits: true
}

def create_user_account(account_id, external_id \\ 0) do
  Tigerbeetle.create_account(
    account_id,
    default_casino_ledger_id(),
    user_liability_code(),
    @liability_account_flags,
    external_id
  )
end
```

### Deposit Flow

When a user deposits money, we:
1. **Debit** the Cash Asset account (money coming in)
2. **Credit** the User Liability account (we now owe this money to the user)

```elixir
def deposit_to_user_account(deposit_id, user_account_id, amount) when amount > 0 do
  with {:ok, %{id: user_liability_id, ledger: ledger}} <-
         fetch_account(user_account_id, user_liability_code()),
       {:ok, %{id: cash_asset_id}} <- ensure_cash_asset_account(ledger),
       {:ok, []} <-
         deposit(deposit_id, user_liability_id, cash_asset_id, ledger, amount) do
    :ok
  end
end

defp deposit(deposit_id, user_liability_id, cash_asset_id, ledger, amount) do
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
```

### Withdrawal Flow

Withdrawal is the reverse of deposit:
1. **Debit** the User Liability account (reduce what we owe)
2. **Credit** the Cash Asset account (money going out)

```elixir
def withdraw_from_user_account(withdrawal_id, user_account_id, amount) when amount > 0 do
  with {:ok, %{id: user_liability_id, ledger: ledger}} <-
         fetch_account(user_account_id, user_liability_code()),
       {:ok, %{id: cash_asset_id}} <- ensure_cash_asset_account(ledger),
       {:ok, []} <-
         withdraw(withdrawal_id, user_liability_id, cash_asset_id, ledger, amount) do
    :ok
  end
end

defp withdraw(withdrawal_id, user_liability_id, cash_asset_id, ledger, amount) do
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
```

### Bet Flow

When a user places a bet:
1. **Debit** the User Liability account (reduce their balance)
2. **Credit** the Game Bet Pool account (hold the bet in escrow)

The bet amount is held in a game-specific pool until the outcome is determined:

```elixir
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
```

Note how TigerBeetle automatically prevents overspending thanks to the `debits_must_not_exceed_credits` flag we set on liability accounts!

### Win Flow

When a user wins, two transfers happen:
1. Return the original bet amount from the Game Pool to the User
2. Pay the additional winnings from the Cash Asset to the User

```elixir
def win_on_game(bet_id, win_amount) do
  with {:ok,
        %{credit_account_id: game_bet_pool_liability_id, debit_account_id: user_liability_id} =
          bet_transfer} <- fetch_transfer(bet_id, TransferType.bet()),
       {:ok, %{id: cash_asset_id}} <-
         fetch_account(cash_asset_account_id(), Account.cash_asset_code()) do
    
    # Transfer 1: Return bet amount from game pool
    transfer_one = %TigerBeetlex.Transfer{
      id: ID.generate(),
      credit_account_id: user_liability_id,
      debit_account_id: game_bet_pool_liability_id,
      ledger: bet_transfer.ledger,
      code: TransferType.win(),
      amount: bet_transfer.amount,
      flags: struct(TigerBeetlex.TransferFlags, %{})
    }

    # Transfer 2: Pay additional winnings from cash asset
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
```

### Loss Flow

When a user loses, the bet amount moves from the Game Pool to the Cash Asset (platform keeps the money):

```elixir
def loss_on_game(bet_id) do
  with {:ok,
        %{credit_account_id: game_bet_pool_liability_id, amount: bet_amount} = bet_transfer} <-
         fetch_transfer(bet_id, TransferType.bet()),
       {:ok, %{id: cash_asset_id}} <-
         fetch_account(cash_asset_account_id(), Account.cash_asset_code()) do
    
    # Transfer bet amount from game pool to cash asset (platform profit)
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
```

## Public APIs

We expose two simple modules for external use:

### Wallet Module

```elixir
defmodule Wallet do
  alias Ledger.Schema.Account

  def get_wallet(wallet_id) when is_integer(wallet_id) do
    Ledger.fetch_account(wallet_id, Account.user_liability_code())
  end

  def create_wallet(wallet_id, external_id \\ 0) when is_integer(wallet_id) do
    Ledger.create_user_account(wallet_id, external_id)
  end

  def deposit(tx_id, wallet_id, amount) when is_integer(wallet_id) do
    Ledger.deposit_to_user_account(tx_id, wallet_id, amount)
  end

  def withdraw(tx_id, wallet_id, amount) when is_integer(wallet_id) do
    Ledger.withdraw_from_user_account(tx_id, wallet_id, amount)
  end
end
```

### GamePlay Module

```elixir
defmodule GamePlay do
  def bet(user_account_id, game_account_id, bet_amount) do
    Ledger.bet_on_game(user_account_id, game_account_id, bet_amount)
  end

  def win(bet_id, win_amount) do
    Ledger.win_on_game(bet_id, win_amount)
  end

  def loss(bet_id) do
    Ledger.loss_on_game(bet_id)
  end
end
```

## Visualizing the Money Flow

Here's how money flows through our system for different operations:

### Deposit ($100)
```
┌─────────────────┐         ┌─────────────────┐
│   Cash Asset    │         │ User Liability  │
│   (code=10)     │         │   (code=30)     │
├─────────────────┤         ├─────────────────┤
│ Debit: +100     │ ──────▶ │ Credit: +100    │
│ Credit: 0       │         │ Debit: 0        │
└─────────────────┘         └─────────────────┘
```

### Bet ($20)
```
┌─────────────────┐         ┌─────────────────┐
│ User Liability  │         │  Game Bet Pool  │
│   (code=30)     │         │   (code=20)     │
├─────────────────┤         ├─────────────────┤
│ Debit: +20      │ ──────▶ │ Credit: +20     │
└─────────────────┘         └─────────────────┘
```

### Win ($50 on a $20 bet)
```
Transfer 1: Return bet from pool
┌─────────────────┐         ┌─────────────────┐
│  Game Bet Pool  │         │ User Liability  │
├─────────────────┤         ├─────────────────┤
│ Debit: +20      │ ──────▶ │ Credit: +20     │
└─────────────────┘         └─────────────────┘

Transfer 2: Pay winnings
┌─────────────────┐         ┌─────────────────┐
│   Cash Asset    │         │ User Liability  │
├─────────────────┤         ├─────────────────┤
│ Credit: +30     │ ──────▶ │ Credit: +30     │
└─────────────────┘         └─────────────────┘
```

### Loss ($20 bet)
```
┌─────────────────┐         ┌─────────────────┐
│  Game Bet Pool  │         │   Cash Asset    │
├─────────────────┤         ├─────────────────┤
│ Debit: +20      │ ──────▶ │ Credit: +20     │
└─────────────────┘         └─────────────────┘
```

## Running the Tests

```bash
# Start TigerBeetle first
➜ tigerbeetle start --addresses=3000 --development ./0_0.tigerbeetle

# Run the tests
➜ mix test
```

Example test for the betting flow:

```elixir
test "it should bet on a game", %{user_account_id: user_account_id, game_id: game_id} do
  # given
  initial_balance = 100
  bet_amount = 10
  deposit_to_user_account(user_account_id, initial_balance)

  # when
  assert {:ok, _bet_id} = GamePlay.bet(user_account_id, game_id, bet_amount)

  # then - user balance is reduced
  assert {:ok, %{credits_posted: ^initial_balance, debits_posted: ^bet_amount}} =
           Tigerbeetle.lookup_account(user_account_id)

  # game pool received the bet
  assert {:ok, %{debits_posted: 0, credits_posted: ^bet_amount}} =
           Tigerbeetle.lookup_account(game_id)
end
```

## Key Takeaways

1. **TigerBeetle enforces double-entry** — Every transfer must have a debit and credit account in the same ledger.

2. **Account flags provide guardrails** — The `debits_must_not_exceed_credits` flag on liability accounts automatically prevents overspending.

3. **Immutable audit trail** — All transfers are immutable. You can always trace the history of any account.

4. **High performance** — TigerBeetle is designed for millions of transfers per second, making it ideal for high-volume gaming platforms.

5. **Correctness by design** — The database schema itself enforces accounting rules, reducing bugs in application code.

## Conclusion

We've built a complete double-entry ledger system for an iGaming platform using Elixir and TigerBeetle. The system handles:

- ✅ User wallet creation with overdraft protection
- ✅ Deposits and withdrawals
- ✅ Placing bets with balance validation
- ✅ Processing wins with proper fund distribution
- ✅ Processing losses with platform revenue capture

The full source code is available on [GitHub](https://github.com/altuntasfatih/ledger).

If you have questions or feedback, feel free to reach out! 🚀

---

*This is Part 2 of the Double-Entry Bookkeeping series. Check out [Part 1](https://medium.com/@altuntasfatih42/how-to-build-a-double-entry-ledger-f69edcea825d) for the fundamentals.*
