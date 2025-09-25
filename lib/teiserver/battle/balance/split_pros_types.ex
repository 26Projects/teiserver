defmodule Teiserver.Battle.Balance.SplitProsTypes do
  @moduledoc false

  @type player :: %{
          rating: float(),
          id: any(),
          name: String.t(),
          uncertainty: float(),
          rank: any()
        }

  @type state :: %{
          players: [player],
          anchors: [player],
          others: [player]
        }

  @type result :: %{
          first_team: [player()],
          second_team: [player()],
          logs: [String.t()]
        }
end
