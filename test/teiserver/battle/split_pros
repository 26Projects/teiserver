defmodule Teiserver.Battle.Balance.SplitPros do
  @moduledoc """
  SplitPros Kill-Switch:
  - Ignores parties/avoids (treats everyone as solo).
  - Anchors the top 2 OS players on opposite teams (sticky).
  - Minimizes team total OS difference while discouraging hoarding of the most
    common tens-bin on the highest-anchor's team.

  Scoring: score = diff + lambda * hoarding_penalty
  """

  alias Teiserver.Battle.Balance.BalanceTypes, as: BT
  alias Teiserver.Battle.Balance.SplitNoobsTypes, as: SN

  # --- Tuning Parameters ---
  @max_iters 200
  # λ (lambda) controls how strongly to discourage hoarding.
  # - Increase this (e.g. 3.0+) to make hoarding reduction dominate over total diff.
  # - Decrease this (e.g. 1.0–1.5) to prioritize pure 50/50 balance.
  @lambda 2.0

  # Margin of tolerance for bin counts.
  # - Default 1 means it’s okay if the anchor’s team has up to 1 more from the common bin.
  # - Raise this if you want to allow slightly more hoarding.
  @bin_margin 1

  @spec perform([BT.expanded_group()], non_neg_integer(), keyword()) :: %{
          team_groups: map(),
          team_players: map(),
          logs: [String.t()]
        }
  def perform(expanded_group, team_count, _opts \\ []) do
    if team_count != 2 do
      raise ArgumentError, "split_pros only supports 2 teams"
    end

    # Kill switch: flatten everyone to per-player (ignore parties/avoids)
    players =
      for %{
            members: members,
            ratings: ratings,
            names: names,
            ranks: ranks,
            uncertainties: uncertainties
          } <- expanded_group,
          {id, rating, name, rank, sigma} <- Enum.zip([members, ratings, names, ranks, uncertainties]) do
        %{id: id, name: name, rating: rating, rank: rank, uncertainty: sigma}
      end

    # Seed: sticky anchors + closest-above/below average; then greedy draft
    {a0, b0, logs0} = seed_splitpros(players)

    # Local search: best-improvement 1-for-1 swaps, anchors sticky
    {aF, bF, logsF} = improve_until_local_optimum(players, a0, b0, @max_iters)

    %{
      team_groups: %{
        1 => to_team_groups(aF),
        2 => to_team_groups(bF)
      },
      team_players: %{
        1 => Enum.map(aF, & &1.id),
        2 => Enum.map(bF, & &1.id)
      },
      logs: logs0 ++ logsF ++ summarize(aF, bF)
    }
  end

  # --- Seeding (anchors + closest above/below + greedy draft) ---

  defp seed_splitpros(players) do
    sorted = Enum.sort_by(players, & &1.rating, :desc)
    [anchor1, anchor2 | rest] = sorted

    avg_rest = Enum.sum(Enum.map(rest, & &1.rating)) / max(length(rest), 1)
    {above, below} = closest_above_below(rest, avg_rest)

    a = Enum.reject([anchor1, above], &is_nil/1)
    b = Enum.reject([anchor2, below], &is_nil/1)

    remaining =
      rest
      |> Enum.reject(&(&1 == above))
      |> Enum.reject(&(&1 == below))
      |> Enum.sort_by(& &1.rating, :desc)

    {a1, b1} =
      Enum.reduce(remaining, {a, b}, fn p, {ta, tb} ->
        if pick_priority(ta) > pick_priority(tb), do: {[p | ta], tb}, else: {ta, [p | tb]}
      end)

    a1s = Enum.sort_by(a1, & &1.rating, :desc)
    b1s = Enum.sort_by(b1, & &1.rating, :desc)

    logs = [
      "Seed anchors: #{anchor1.name}(#{ff(anchor1.rating)}) | #{anchor2.name}(#{ff(anchor2.rating)})",
      "Closest to avg: above=#{fmtp(above)} below=#{fmtp(below)}",
      "Post-seed totals: A=#{ff(sum(a1s))} B=#{ff(sum(b1s))} diff=#{ff(diff(a1s,b1s))}"
    ]

    {a1s, b1s, logs}
  end

  defp closest_above_below(players, avg) do
    above =
      players
      |> Enum.filter(&(&1.rating >= avg))
      |> Enum.min_by(&(abs(&1.rating - avg)), fn -> nil end)

    below =
      players
      |> Enum.filter(&(&1.rating < avg))
      |> Enum.min_by(&(abs(&1.rating - avg)), fn -> nil end)

    {above, below}
  end

  defp pick_priority(team) do
    team_rating = sum(team)
    cap = Enum.max_by(team, & &1.rating, fn -> %{rating: 0.0} end).rating
    team_rating * -1 + length(team) * -100 + cap * -1
  end

  # --- Local search with hoarding-aware score ---

  defp improve_until_local_optimum(players, a, b, max_iters) do
    common_bin = most_common_bin(players)
    top2 = Enum.take(Enum.sort_by(players, & &1.rating, :desc), 2)
    {top_anchor, _} = {hd(top2), List.last(top2)}

    current = score(a, b, top_anchor, common_bin)
    do_improve(players, a, b, top_anchor, common_bin, current, 0, max_iters, [])
  end

  defp do_improve(_players, a, b, _top_anchor, _cb, current, iters, max_iters, logs)
       when iters >= max_iters,
       do: {a, b, logs ++ ["Stop: iteration cap (#{iters}/#{max_iters}), score=#{ff(current)}"]}

  defp do_improve(players, a, b, top_anchor, cb, current, iters, max_iters, logs) do
    # Generate all candidate 1-for-1 swaps excluding anchors
    {a_swaps, b_swaps} =
      {Enum.reject(a, &(&1.id == top_anchor.id)), Enum.reject(b, &(&1.id == top_anchor.id))}

    {best_delta, best_pair} =
      for x <- a_swaps, y <- b_swaps do
        a2 = replace(a, x, y)
        b2 = replace(b, y, x)
        s2 = score(a2, b2, top_anchor, cb)
        {current - s2, {x, y, a2, b2, s2}}
      end
      |> Enum.max_by(fn {delta, _} -> delta end, fn -> {0.0, nil} end)

    cond do
      best_pair == nil or best_delta <= 0.0 ->
        {a, b, logs ++ ["Stop: local optimum; score=#{ff(current)}"]}

      true ->
        {_x, _y, a2, b2, s2} = best_pair
        do_improve(players, a2, b2, top_anchor, cb, s2, iters + 1, max_iters,
          logs ++ ["Swap improves score → #{ff(current)} → #{ff(s2)} (iter #{iters + 1})"]
        )
    end
  end

  # --- Scoring & penalties ---

  defp score(a, b, top_anchor, common_bin) do
    diff = diff(a, b)
    penalty = hoarding_penalty(a, b, top_anchor, common_bin)
    diff + @lambda * penalty
  end

  defp hoarding_penalty(a, b, top_anchor, cb) do
    {top_team, other_team} = if Enum.any?(a, &(&1.id == top_anchor.id)), do: {a, b}, else: {b, a}
    ca = bin_count(top_team, cb)
    cbn = bin_count(other_team, cb)

    # Penalty grows quadratically with excess hoarding
    excess = max(0, ca - cbn - @bin_margin)
    excess * excess
  end

  # --- Utilities ---

  defp most_common_bin(players) do
    players
    |> Enum.map(&tens_bin(&1.rating))
    |> Enum.frequencies()
    |> Enum.max_by(fn {_bin, cnt} -> cnt end)
    |> elem(0)
  end

  defp tens_bin(v), do: div(floor(v), 10) * 10

  defp bin_count(team, bin),
    do: Enum.count(team, fn p -> tens_bin(p.rating) == bin end)

  defp sum(team), do: Enum.reduce(team, 0.0, fn p, acc -> acc + p.rating end)
  defp diff(a, b), do: abs(sum(a) - sum(b))

  defp replace(list, old, new),
    do: [new | Enum.reject(list, &(&1.id == old.id))] |> Enum.sort_by(& &1.rating, :desc)

  defp to_team_groups(team) do
    Enum.map(team, fn x ->
      %{members: [x.id], count: 1, group_rating: x.rating, ratings: [x.rating]}
    end)
  end

  defp ff(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp ff(v), do: to_string(v)
  defp fmtp(nil), do: "nil"
  defp fmtp(p), do: "#{p.name}(#{ff(p.rating)})"

  defp summarize(a, b) do
    cb = most_common_bin(a ++ b)
    [
      "Final diff=#{ff(diff(a,b))}, common_bin=#{cb}, " <>
        "bin_counts A=#{bin_count(a,cb)} B=#{bin_count(b,cb)}"
    ]
  end
end
