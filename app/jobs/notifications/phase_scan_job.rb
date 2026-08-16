# frozen_string_literal: true

module Notifications
  # 予約を取りこぼした交換会を拾う網。
  #
  # 変わり目そのものは Notifications::PhaseCheckJob の予約が拾う。ここが要るのは、
  # 予約が queue のデータベースにしか無いためで、積み損ねたときも、ジョブが失敗して
  # 止まったときも、予約は自分では戻ってこない。走査は状態を持たないので、
  # 原因が直れば次の回で何事もなかったように再開する。
  #
  # 走査は全件を見る。終わった交換会を外す条件を足すと、日時を動かされた交換会が
  # 走査から落ちたことに気付けない
  class PhaseScanJob < ApplicationJob
    def perform
      # 現在時刻はここで1回だけ読む。走査の途中で読み直すと、境目にいる交換会を
      # 前半と後半で違うフェーズとして見る（docs/spec.md 11.）
      Notifications::PhaseChange.deliver_all(at: Time.current)
    end
  end
end
