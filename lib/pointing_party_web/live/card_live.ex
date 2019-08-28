defmodule PointingPartyWeb.CardLive do
  use Phoenix.LiveView
  alias PointingPartyWeb.CardView
  alias PointingPartyWeb.Endpoint
  alias PointingPartyWeb.Presence

  alias PointingParty.{Card, VoteCalculator}

  def render(assigns) do
    # render the LiveView template here
    Phoenix.View.render(CardView, "index.html", assigns)
  end

  def mount(%{username: username}, socket) do
    #LiveView and Presence subscribe to the same topic!!!
    Endpoint.subscribe("pointing_party", [])
    {:ok, _} = Presence.track(
                  self(),
                  "pointing_party",
                  username,
                  %{points: nil})



    {:ok, assign(socket, initial_state(username))}
  end

  # LiveView event ~ View change
  def handle_event("start_party", _value, socket) do
    [current_card | remaining_cards] = Card.cards()
#    socket = assign(socket,
#      is_pointing: true,
#      current_card: current_card,
#      remaining_cards: remaining_cards)
#
    payload = %{card: current_card, remaining: remaining_cards}

    Endpoint.broadcast("pointing_party", "party_started", payload)
    {:noreply, socket}
  end

  def handle_event("vote_submit", %{"points" => points}, socket) do
    #IO.puts "SUBMITED VOTE"
    Presence.update(self(), "pointing_party", socket.assigns.username, %{points: points})
    #if everyone voted
    #tally
    #broadcast


    if everyone_voted?() do
      {outcome, point_tally} = VoteCalculator.calculate_votes(Presence.list("pointing_party"))
      Endpoint.broadcast("pointing_party", "votes_calculated", %{outcome: outcome, point_tally: point_tally})
    end
    {:noreply, socket}
  end

  def handle_event("next_card", points, socket) do
    IO.puts "handle_event next_card"
    Endpoint.broadcast("pointing_party", "next_card", %{points: points})
    {:noreply, socket}
    # get the next card
    # broadcast

  end

  #PubSub message ~ broadcasting
  def handle_info(%{event: "next_card", payload: %{points: points}}, socket) do
    IO.puts "handle_info next_card"
    updated_socket = save_vote_next_card(points, socket)
    Presence.update(self(), "pointing_party", socket.assigns.username, %{points: nil})
    {:noreply, updated_socket}
  end

  def handle_info(%{event: "votes_calculated", payload: payload}, socket) do
    updated_socket =
    socket
    |> assign(:outcome, payload.outcome)
    |> assign(:point_tally, payload.point_tally)
    {:noreply, updated_socket}
  end


  def handle_info(%{event: "presence_diff", payload: payload}, socket) do
    users = Presence.list("pointing_party")
    #socket.assigns todo
    {:noreply, assign(socket, users: users)}
  end

  def handle_info(%{
    event: "party_started",
    payload: %{card: card, remaining: remaining},
    topic: "pointing_party"}, socket) do

    {:noreply, assign(socket,
               current_card: card,
               remaining_cards: remaining,
               is_pointing: true)}
  end


  def everyone_voted? do

    "pointing_party"
    |> Presence.list()
    |> Enum.map(fn{_username, %{metas: [%{points: points}]}} -> points end)
    |> Enum.all?(&(&1))
  end

    ## Helper Methods ##

  defp initial_state(username) do
    [
      current_card: nil,
      outcome: nil,
      is_pointing: false,
      remaining_cards: [],
      completed_cards: [],
      point_tally: nil,
      users: [],
      username: username
    ]
  end

  defp save_vote_next_card(points, socket) do
    latest_card =
      socket.assigns
      |> Map.get(:current_card)
      |> Map.put(:points, points)

    {next_card, remaining_cards} =
      socket.assigns
      |> Map.get(:remaining_cards)
      |> List.pop_at(0)

    socket
    |> assign(:remaining_cards, remaining_cards)
    |> assign(:current_card, next_card)
    |> assign(:outcome, nil)
    |> assign(:points, nil)
    |> assign(:completed_cards, [latest_card | socket.assigns[:completed_cards]])
  end
end
