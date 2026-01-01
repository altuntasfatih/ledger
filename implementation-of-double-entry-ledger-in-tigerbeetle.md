# Building a Double-Entry Ledger with Elixir and TigerBeetle

In the [previous article](https://medium.com/@altuntasfatih42/how-to-build-a-double-entry-ledger-f69edcea825d), we explored the fundamentals of double-entry bookkeeping — the accounting system that has powered financial record-keeping for over 500 years. We walked through how debits and credits work, why every transaction needs two sides, and how this creates a self-balancing, auditable system.

Now it's time to turn theory into practice. In this follow-up, we'll implement a production-ready ledger system for an iGaming platform using **Elixir** and **TigerBeetle**. While we'll include some code, our focus will be on the *why* behind each design decision.

---

## Why TigerBeetle?

When we first built our ledger on PostgreSQL, it worked well — until it didn't. As our transaction volume grew, we hit performance bottlenecks and had to implement increasingly complex locking strategies to maintain consistency.

**TigerBeetle** is a purpose-built financial database designed for exactly this problem. Here's what makes it different:

- **Pre-defined double-entry schema**: Unlike general-purpose databases where you design your own tables, TigerBeetle comes with accounts and transfers built in. This isn't a limitation — it's an advantage. The database *understands* accounting.

- **Immutable audit trail**: Every transfer is permanent. You can't delete or modify history, which is exactly what regulators and auditors want.

- **Built-in balance protection**: TigerBeetle can enforce that accounts never go negative — at the database level, not in your application code.

- **Extreme performance**: Designed for millions of transfers per second with strict consistency guarantees.

The key insight is that TigerBeetle's constraints *reduce* bugs. When the database enforces accounting rules, your application code becomes simpler and safer.

---

## Getting Started with TigerBeetle

Setting up TigerBeetle is straightforward. After installation, you create a data file (where TigerBeetle stores everything) and start the server:

```bash
# Format a new data file
tigerbeetle format --cluster=0 --replica=0 --replica-count=1 --development 0_0.tigerbeetle

# Start the server
tigerbeetle start --addresses=3000 --development ./0_0.tigerbeetle
```

You can immediately test it via the REPL:

```bash
tigerbeetle repl --cluster=0 --addresses=3000
```

```sql
create_accounts id=1 code=10 ledger=700, id=2 code=10 ledger=700;
create_transfers id=1 debit_account_id=1 credit_account_id=2 amount=10 ledger=700 code=10;
lookup_accounts id=1, id=2;
```

This creates two accounts and transfers 10 units between them. Account 1 shows `debits_posted: 10`, Account 2 shows `credits_posted: 10` — double-entry bookkeeping in action.

---

## Designing the Account Structure

Before writing any code, we need to think about our account types. In TigerBeetle, every account has a `code` field — an integer that identifies what *type* of account it is. This is crucial for our ledger logic.

For an iGaming platform, we need:

| Account Type | Code | Purpose |
|-------------|------|---------|
| **Cash Asset** | 10 | Platform's actual money holdings |
| **Game Bet Pool** | 20 | Holds active bets during games |
| **User Liability** | 30 | What we owe to each user (their balance) |
| **System Revenue** | 40 | Platform earnings |
| **System Capital** | 50 | Initial platform investment |

### Why "Liability" for User Balances?

This is a common point of confusion. When a user deposits $100, we're not giving them an "asset" — we're creating a *liability*. That $100 in their wallet represents money we *owe* them. When they withdraw, we're settling that debt.

This matters because:
- **Credits increase liabilities** (we owe more)
- **Debits decrease liabilities** (we owe less)

When users deposit, we credit their account. When they bet or withdraw, we debit it. The accounting equation stays balanced.

---

## The Power of Account Flags

TigerBeetle allows you to set flags on accounts that enforce business rules at the database level. For user accounts, we set:

```elixir
@liability_account_flags %{
  debits_must_not_exceed_credits: true
}
```

This single flag eliminates an entire class of bugs. Users *cannot* spend more than they have — TigerBeetle will reject the transfer with an `exceeds_credits` error. No race conditions, no double-spending, no "oops we let them go negative" bugs.

This is fundamentally different from checking balances in application code:

```elixir
# ❌ WRONG: Race condition possible
if user.balance >= amount do
  debit(user, amount)  # Another request could sneak in here!
end

# ✅ RIGHT: Let TigerBeetle enforce it
case create_transfer(debit: user, amount: amount) do
  {:error, :exceeds_credits} -> {:error, :insufficient_funds}
  :ok -> :ok
end
```

---

## Understanding Transfer Types

Just as accounts have codes, transfers have codes too. This lets us categorize and query different transaction types:

| Transfer Type | Code | Description |
|--------------|------|-------------|
| **Deposit** | 1 | User adds funds |
| **Withdrawal** | 2 | User removes funds |
| **Bet** | 3 | User places a wager |
| **Win** | 4 | User receives winnings |
| **Loss** | 5 | Bet amount goes to platform |

These codes aren't just for display — they're essential for:
- **Auditing**: "Show me all deposits this month"
- **Business logic**: Finding the original bet when processing wins/losses
- **Reporting**: Calculating revenue, player lifetime value, etc.

---

## The Money Flows

Let's trace how money moves through our system for each operation. Understanding these flows is more important than the code itself.

### Deposit: User Adds $100

When a user deposits money, two things happen simultaneously:

1. **Cash Asset gets debited (+$100)**: Real money entered our system
2. **User Liability gets credited (+$100)**: We now owe the user $100

```
Cash Asset          User Liability
─────────────       ─────────────
Debit: +$100   →    Credit: +$100
```

The user's "balance" is their liability account's credits minus debits. After this deposit, that's $100 - $0 = $100.

### Bet: User Wagers $20

When placing a bet, money moves from the user to an escrow-like "game pool":

1. **User Liability gets debited (+$20)**: User's balance decreases
2. **Game Pool gets credited (+$20)**: Bet is held in escrow

```
User Liability      Game Pool
─────────────       ─────────────
Debit: +$20    →    Credit: +$20
```

The user's balance is now $100 - $20 = $80. The $20 sits in the game pool until the outcome is determined.

### Win: User Wins $50 (on a $20 bet)

Winning requires *two* transfers:

**Transfer 1: Return the original bet**
```
Game Pool           User Liability
─────────────       ─────────────
Debit: +$20    →    Credit: +$20
```

**Transfer 2: Pay additional winnings from platform**
```
Cash Asset          User Liability
─────────────       ─────────────
Debit: +$30    →    Credit: +$30
```

The game pool returns to zero (the bet is settled), and the user receives their original $20 plus $30 in profit. Their balance is now $80 + $50 = $130.

### Loss: User Loses the $20 Bet

When a user loses, the bet moves from the game pool to the platform's cash:

```
Game Pool           Cash Asset
─────────────       ─────────────
Debit: +$20    →    Credit: +$20
```

The user's balance stays at $80 (they already "spent" the $20 when betting). The platform keeps the money.

---

## Architecture: Separation of Concerns

Our implementation separates the codebase into focused modules:

### `Ledger.Wallet` — User Account Operations

This module handles everything wallet-related:
- **Creating wallets** with proper flags
- **Deposits and withdrawals** with balance validation
- **Balance queries**

The key design decision here is that wallets are *always* liability accounts with overdraft protection. This is enforced at creation time, not checked on each transaction.

### `Ledger.GamePlay` — Betting Operations

Game-specific logic lives here:
- **Placing bets** (with automatic insufficient-funds handling)
- **Processing wins** (two-transfer atomic operation)
- **Processing losses** (single transfer to platform)

One important detail: when processing a win, we look up the *original bet transfer* to find:
- Which accounts were involved
- What amount was bet
- Which ledger to use

This creates an audit trail linking wins/losses back to their originating bets.

### `Ledger.Tigerbeetle` — Database Wrapper

This thin layer handles:
- Connection management
- ID normalization (integers ↔ binary)
- Error translation

It's intentionally minimal — we don't want business logic hiding in the database layer.

### `Ledger.Codes` — Type Definitions

Account and transfer codes are defined in dedicated modules with clear documentation. This makes the codebase self-documenting and prevents "magic number" confusion.

---

## Handling Edge Cases

### Ensuring System Accounts Exist

The cash asset account must exist before any deposit can occur. Rather than requiring manual setup, we use an "ensure" pattern:

1. Try to query for the account
2. If not found, create it
3. Return the account ID

This makes the system self-initializing while remaining idempotent (creating twice is safe).

### Game Pool Accounts

Each game gets its own bet pool account, created on-demand when the first bet is placed. The account ID matches the game ID, making lookups trivial and ensuring bets for different games stay isolated.

### Atomic Multi-Transfer Operations

Win processing requires two transfers that must succeed or fail together. TigerBeetle supports batch transfers — if any transfer in a batch fails, none are applied. This guarantees we never partially pay a winner.

---

## What TigerBeetle Gives Us for Free

Reflecting on this implementation, here's what we *didn't* have to build:

1. **Balance tracking** — TigerBeetle maintains `credits_posted` and `debits_posted` automatically
2. **Overdraft prevention** — The `debits_must_not_exceed_credits` flag handles this
3. **Audit trail** — All transfers are immutable and queryable
4. **Race condition handling** — TigerBeetle's consistency model eliminates them
5. **Transaction isolation** — Batch operations are atomic

In a traditional database, each of these would require careful implementation and testing. With TigerBeetle, they're guaranteed by the database itself.

---

## Testing Strategy

Testing a ledger system requires verifying that:
1. Accounts have correct balances after operations
2. Invalid operations are rejected (insufficient funds, etc.)
3. Multi-step flows work correctly (bet → win/loss)

Our tests follow the pattern:
1. Set up accounts with known balances
2. Perform operations
3. Query accounts and verify balances match expectations

The key insight is that **TigerBeetle doesn't have transactions to roll back** — each test run needs a fresh database. For testing, we recreate the data file before each test suite.

---

## Key Takeaways

1. **Let the database do the heavy lifting**: TigerBeetle's constraints eliminate bugs that would require complex application code in a general-purpose database.

2. **Account types matter**: Using codes to categorize accounts enables powerful queries and cleaner business logic.

3. **Think in money flows**: Before writing code, diagram how money moves between accounts. The code should mirror these flows exactly.

4. **Liability accounts for user balances**: This isn't just accounting pedantry — it correctly models that user deposits create an obligation to repay.

5. **Atomic operations for multi-transfer scenarios**: When wins require two transfers, batch them to guarantee all-or-nothing execution.

---

## Conclusion

We've built a complete double-entry ledger system that handles:

- ✅ User wallet management with automatic overdraft protection
- ✅ Deposits and withdrawals with full audit trails
- ✅ Bet placement with real-time balance validation
- ✅ Win processing with atomic fund distribution
- ✅ Loss processing with platform revenue capture

The full source code is available on [GitHub](https://github.com/altuntasfatih/ledger).

What surprised me most about this implementation was how *little* code we needed. By choosing a database that understands accounting, we could focus on business logic instead of fighting infrastructure.

If you're building any system that handles money — whether gaming, payments, or marketplace transactions — I'd encourage you to look at TigerBeetle. The constraints it imposes aren't limitations; they're guardrails that make correctness the default.

---

*This is Part 2 of the Double-Entry Bookkeeping series. Check out [Part 1](https://medium.com/@altuntasfatih42/how-to-build-a-double-entry-ledger-f69edcea825d) for the fundamentals of double-entry accounting.*

*Questions or feedback? Reach out on [Twitter/X](https://twitter.com/altuntasfatih) or leave a comment below!* 🚀
