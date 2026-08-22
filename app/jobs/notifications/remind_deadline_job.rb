# frozen_string_literal: true

module Notifications
  # 締切は交換会の日時カラムそのものなので、ウィンドウが開く時刻を予約して確認しに行く。
  # 定期的に全件を見に回るより、ウィンドウの縁を直接指せる。
  #
  # 予約を取り消さない理由は Notifications::NotifyPhaseChangeJob と同じで、
  # 実行時に締切を導出して記録と突き合わせるのは Notifications::DeadlineReminder
  class RemindDeadlineJob < ApplicationJob
    # どの締切を持つかは交換会が決める（Exchange::REMINDER_DEADLINES）。
    # 何時間前に知らせるかはリマインドの都合なので、引き算はこちらに置く。
    # 過ぎた時刻を渡されたら待たずに走り、ウィンドウの中かどうかを実行時に見る
    def self.reserve(exchange, deadlines:)
      deadlines.each { set(wait_until: it - Notifications::DeadlineReminder::WINDOW).perform_later(exchange) }
    end

    # 予約は数週間先まで残る。その間に交換会が消えることがあり、消えていれば
    # 確かめる締切も知らせる相手も無い。失敗として残さない
    discard_on ActiveJob::DeserializationError

    def perform(exchange)
      # 予約した時刻ではなく実際に走った時刻で見る。
      # 遅れて走ったなら、遅れた時点の締切が正しい
      Notifications::DeadlineReminder.new(exchange, at: Time.current).deliver
    end
  end
end
