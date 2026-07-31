# frozen_string_literal: true

class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.references :participation, null: false, foreign_key: true
      t.string :title, null: false
      t.text :summary
      t.string :url
      t.text :recommendation
      # #20 で Active Record Encryption を掛ける。暗号化後のペイロードは
      # 平文より大幅に長くなり varchar(255) に収まらないため text にしてある
      t.text :gift_code, null: false

      t.timestamps
    end
  end
end
