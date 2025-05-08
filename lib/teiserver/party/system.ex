defmodule Teiserver.Party.System do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      Teiserver.Party.Registry,
      Teiserver.Party.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
