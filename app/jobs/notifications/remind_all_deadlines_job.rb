# frozen_string_literal: true

module Notifications
  # Notifications::RemindDeadlineJob の予約を取りこぼした交換会を拾う定期走査。
  # 要る理由と全件を見る理由は Notifications::NotifyAllPhaseChangesJob と同じ
  class RemindAllDeadlinesJob < ApplicationJob
    def perform
      # 走査の途中で現在時刻を読み直すと、ウィンドウの縁にいる交換会を
      # 前半と後半で違う扱いにする
      Notifications::DeadlineReminder.deliver_all(at: Time.current)
    end
  end
end
