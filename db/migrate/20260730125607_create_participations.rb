# frozen_string_literal: true

class CreateParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :participations do |t|
      t.references :exchange, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :participations, [:exchange_id, :user_id], unique: true
  end
end
