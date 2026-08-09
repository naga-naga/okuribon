# frozen_string_literal: true

class AddDraftPositionToParticipations < ActiveRecord::Migration[8.1]
  def change
    # スネークドラフトの抽選順。マッチングを実行して初めて決まるため、
    # 実行前と実行済みを区別できるよう NULL を許す。
    # Engine は毎回この並びを返しているが保存していなかった。読むときにシードから
    # 引き直すこともできるものの、Engine の内部（乱数の消費順）に画面が依存する
    add_column :participations, :draft_position, :integer
  end
end
