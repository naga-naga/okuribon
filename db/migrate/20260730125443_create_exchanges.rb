# frozen_string_literal: true

class CreateExchanges < ActiveRecord::Migration[8.1]
  def change
    create_table :exchanges do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.datetime :registration_starts_at, null: false
      t.datetime :registration_ends_at, null: false
      t.datetime :wish_starts_at, null: false
      t.datetime :wish_ends_at, null: false
      t.datetime :matched_at
      t.string :invite_token, null: false
      t.bigint :random_seed, null: false
      t.string :webhook_url

      t.timestamps
    end

    add_index :exchanges, :invite_token, unique: true
  end
end
