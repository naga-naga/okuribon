# frozen_string_literal: true

class AddUniqueConstraintToWishPositions < ActiveRecord::Migration[8.1]
  def change
    # 順位が重複すると order(:position) の並びが不定になり、乱数シードを固定しても
    # マッチングの結果を再現できなくなる。
    # 並べ替えは順位を1つずつ書き換えるため、途中で必ず重複が生まれる。一意インデックスは
    # 行ごとに検査されるので、退避用の値を経由するような書き方を強いられる。
    # 検査をトランザクションの終わりまで遅らせて、素直に書けるようにする
    add_unique_constraint :wishes, [:participation_id, :position], deferrable: :deferred
  end
end
