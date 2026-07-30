# frozen_string_literal: true

class CreateAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :assignments do |t|
      t.references :book, null: false, foreign_key: true, index: { unique: true }
      t.references :participation, null: false, foreign_key: true
      # 余り物の割当は巡を持たない（Matching::Engine が round: nil を返す）
      t.integer :round
      t.boolean :returned, null: false, default: false

      t.timestamps
    end
  end
end
