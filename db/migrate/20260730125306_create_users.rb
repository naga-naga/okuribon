# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :display_name, null: false
      t.string :avatar_url

      t.timestamps
    end

    add_index :users, [:provider, :uid], unique: true
  end
end
