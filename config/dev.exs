import Config

config :ledger, :tigerbeetlex,
  connection_name: :tb,
  cluster: 0,
  addresses: ["127.0.0.1:3000"]

config :ledger, :ledger_details,
  cash_asset_account_id: 1,
  default_casino_ledger_id: 1
