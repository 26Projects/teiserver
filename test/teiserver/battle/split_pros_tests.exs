defmodule Teiserver.Battle.Balance.SplitProsTest do
  use ExUnit.Case, async: true

  alias Teiserver.Battle.Balance.SplitPros

  # Helper to wrap a plain OS list into the expanded_group shape Teiserver expects
  defp build_group(os_values) do
    Enum.map(Enum.with_index(os_values, 1), fn {rating, idx} ->
      %{
        members: [idx],
        ratings: [rating],
        names: ["Player#{idx}"],
        ranks: [trunc(:rand.uniform() * 5)],
        uncertainties: [2.5],
        count: 1
      }
    end)
  end

  defp tens_bin(v), do: div(floor(v), 10) * 10
  defp bin_count(team, bin), do: Enum.count(team, fn p -> tens_bin(p.rating) == bin end)

  test "basic 16-player case with an 80 anchor and 40s cluster" do
    os_values = [
      80.32, 41.30, 39.14, 36.79, 34.70, 34.24, 33.61, 31.20,
      46.52, 46.28, 45.92, 45.04, 42.19, 37.52, 36.96, 34.27
    ]

    group = build_group(os_values)
    result = SplitPros.perform(group, 2, [])

    assert length(result.first_team) == 8
    assert length(result.second_team) == 8

    diff =
      abs(Enum.sum(Enum.map(result.first_team, & &1.rating)) -
          Enum.sum(Enum.map(result.second_team, & &1.rating)))

    assert diff < 30.0
  end

  test "smaller 10-player case balances into 5v5" do
    os_values = [75.0, 55.0, 50.0, 48.0, 46.0, 45.0, 35.0, 34.0, 33.0, 30.0]

    group = build_group(os_values)
    result = SplitPros.perform(group, 2, [])

    assert length(result.first_team) == 5
    assert length(result.second_team) == 5
  end

  test "handles case where all players are in the same OS bin" do
    os_values = Enum.map(1..16, fn _ -> 40.0 + :rand.uniform(5) end)

    group = build_group(os_values)
    result = SplitPros.perform(group, 2, [])

    assert length(result.first_team) == 8
    assert length(result.second_team) == 8
  end

  test "hoarding-control prevents anchor team from hoarding the most common bin" do
    # Build a case with many 40s plus one strong anchor at 80
    os_values = [
      80.0, 78.0, 42.0, 41.0, 40.5, 40.2, 39.9, 39.5,
      38.0, 37.5, 37.0, 36.5, 36.0, 35.5, 35.0, 34.5
    ]

    group = build_group(os_values)
    result = SplitPros.perform(group, 2, [])

    # Identify the top anchor
    anchor = Enum.max_by(os_values, & &1)

    # Which team has the anchor?
    {anchor_team, other_team} =
      if Enum.any?(result.first_team, &(&1.rating == anchor)) do
        {result.first_team, result.second_team}
      else
        {result.second_team, result.first_team}
      end

    # Find most common tens-bin in the whole lobby
    common_bin =
      os_values
      |> Enum.map(&tens_bin/1)
      |> Enum.frequencies()
      |> Enum.max_by(fn {_bin, count} -> count end)
      |> elem(0)

    anchor_bin_count = bin_count(anchor_team, common_bin)
    other_bin_count = bin_count(other_team, common_bin)

    # The anchor's team should not exceed the other by more than the margin
    assert anchor_bin_count <= other_bin_count + 1
  end
end
