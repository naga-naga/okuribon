# frozen_string_literal: true

# 希望提出期間の開始は登録期間の終了と同時刻でなければならない。
# カラムに分けると二重管理になるため、registration_ends_at から導出する
class RemoveWishStartsAtFromExchanges < ActiveRecord::Migration[8.1]
  def change
    remove_column :exchanges, :wish_starts_at, :datetime, null: false
  end
end
