defmodule Teiserver.Autohost.Autohost do
  @moduledoc false
  use TeiserverWeb, :schema

  @type id :: integer()
  @type t :: %__MODULE__{
          id: id(),
          name: String.t()
        }

  schema "teiserver_autohosts" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(autohost, attrs) do
    autohost
    |> cast(attrs, [:name])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 3, max: 30)
  end
end
