# frozen_string_literal: true

class AddNotifiedPhaseToExchanges < ActiveRecord::Migration[8.1]
  def change
    # 最後にチャンネルへ知らせたフェーズ。定期実行の走査が、いまのフェーズと
    # 食い違ったときだけ投稿するために持つ。
    # 通知履歴のテーブルにしないのは、要るのが「同じフェーズを二度出さない」
    # ことだけだから。履歴を読む画面は無く、行だけが増え続ける。
    # まだ一度も知らせていない状態を NULL で表すため、既定値は置かない
    add_column :exchanges, :notified_phase, :string
  end
end
