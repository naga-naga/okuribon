# frozen_string_literal: true

module Notifications
  # 予約を取りこぼした交換会を拾う定期走査。
  #
  # 締切そのものは Notifications::RemindDeadlineJob の予約が拾う。ここが要るのは、
  # 予約が queue のデータベースにしか無いためで、積み損ねたときも、ジョブが失敗して
  # 止まったときも、予約は自分では戻ってこない。走査は状態を持たないので、
  # 原因が直れば次の回で何事もなかったように再開する。
  #
  # 走査は全件を見る。終わった交換会を外す条件を足すと、日時を動かされた交換会が
  # 走査から落ちたことに気付けない
  class RemindAllDeadlinesJob < ApplicationJob
    def perform
      # 走査の途中で現在時刻を読み直すと、ウィンドウの縁にいる交換会を
      # 前半と後半で違う扱いにする
      Notifications::DeadlineReminder.deliver_all(at: Time.current)
    end
  end
end
