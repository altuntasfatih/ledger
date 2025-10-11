import Config

config :ledger, :tigerbeetlex,
  connection_name: :tb_test,
  cluster: 0,
  addresses: ["127.0.0.1:3001"]

config :ledger, :ledger_details,
  cash_asset_account_id: 11,
  default_casino_ledger_id: 11
