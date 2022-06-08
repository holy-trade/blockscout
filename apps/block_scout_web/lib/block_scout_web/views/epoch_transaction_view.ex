defmodule BlockScoutWeb.EpochTransactionView do
  use BlockScoutWeb, :view

  alias Explorer.Celo.Util
  alias Explorer.Chain.Wei

  def get_reward_currency(reward_type) do
    case reward_type do
      "voter" -> "CELO"
      _ -> "cUSD"
    end
  end
end
