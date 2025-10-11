[
  # Ignore warnings from test support files
  ~r/test\/support\/.*/,

  # Ignore warnings from test files
  ~r/test\/.*\.exs/,

  # Ignore warnings from dependencies
  ~r/deps\/.*/,

  # Ignore specific ExMachina warnings
  {"test/support/factory.ex", :unknown_function}
]
