# frozen_string_literal: true

module Notifications
  # Notifications::NotifyPhaseChangeJob の予約を取りこぼした交換会を拾う定期走査。
  # 予約は queue のデータベースにしか無く、積み損ねても、ジョブが失敗して止まっても、
  # 自分では戻ってこない。走査は状態を持たないので、原因が直れば次の回で再開する。
  #
  # 走査は全件を見る。終わった交換会を外す条件を足すと、日時を動かされた交換会が
  # 走査から落ちたことに気付けない
  class NotifyAllPhaseChangesJob < ApplicationJob
    def perform
      # 走査の途中で現在時刻を読み直すと、境目にいる交換会を
      # 前半と後半で違うフェーズとして見る
      Notifications::PhaseChange.deliver_all(at: Time.current)
    end
  end
end
