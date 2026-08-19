# frozen_string_literal: true

class AddRemindedDeadlineAtToExchanges < ActiveRecord::Migration[8.1]
  def change
    # 最後にリマインドを出した締切の時刻。同じ締切に二度出さないために持つ。
    # フェーズ名ではなく時刻そのものを記録するのは、主催者が締切を動かしたときに
    # 新しい締切のリマインドが出せなくなるため。フェーズ名だと、登録期間のうちに
    # 締切を1週間先へずらしても「登録期間は出し済み」のまま残る。
    # まだ一度も出していない状態を NULL で表すため、既定値は置かない
    add_column :exchanges, :reminded_deadline_at, :datetime
  end
end
