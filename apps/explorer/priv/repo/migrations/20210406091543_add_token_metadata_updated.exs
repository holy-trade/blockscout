defmodule Explorer.Repo.Migrations.AddTokenMetadataUpdated do
  use Ecto.Migration

  def change do
    alter table(:tokens) do
      add(:metadata_updated, :utc_datetime_usec, null: false, default: fragment("now()"))
    end
  end
end
