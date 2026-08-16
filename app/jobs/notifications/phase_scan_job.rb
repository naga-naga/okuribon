# frozen_string_literal: true

module Notifications
  # フェーズの変わり目を拾う定期実行の入口。
  #
  # フェーズは日時から導出され、状態カラムを持たない（docs/spec.md 4.）。
  # 変わった瞬間を知らせてくれるものが無いので、定期的に見に行くしかない。
  #
  # 走査は全件を見る。終わった交換会を外す条件を足すと、日時を動かされた交換会が
  # 走査から落ちたことに気付けない
  class PhaseScanJob < ApplicationJob
    def perform
      # 現在時刻はここで1回だけ読む。走査の途中で読み直すと、境目にいる交換会を
      # 前半と後半で違うフェーズとして見る（docs/spec.md 11.）
      PhaseChange.deliver_all(at: Time.current)
    end
  end
end
