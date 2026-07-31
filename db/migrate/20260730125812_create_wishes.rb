# frozen_string_literal: true

class CreateWishes < ActiveRecord::Migration[8.1]
  def change
    create_table :wishes do |t|
      t.references :participation, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :wishes, [:participation_id, :book_id], unique: true
  end
end
