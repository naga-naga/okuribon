# frozen_string_literal: true

module Notifications
  # 1つの交換会が締切の窓に入ったかを確かめ、入っていれば知らせる。
  #
  # 締切は交換会の日時カラムそのものなので、窓が開く時刻を予約して確認しに行く。
  # 定期的に全件を見に回るより、窓の縁を直接指せる。
  #
  # 予約は取り消さない。主催者が締切を動かしたら新しい時刻を積み足すだけにする。
  # 古い予約が残っても、Notifications::DeadlineReminder が実行時に締切を導出して
  # 記録と突き合わせるので、空振りするか正しいリマインドを出すかのどちらかにしかならない
  class RemindDeadlineJob < ApplicationJob
    # どの締切を持つかは交換会が決める（Exchange::REMINDER_DEADLINES）。
    # 何時間前に知らせるかはリマインドの都合なので、引き算はこちらに置く。
    # 過ぎた時刻を渡されたら待たずに走り、窓の中かどうかを実行時に見る
    def self.reserve(exchange, deadlines:)
      deadlines.each { set(wait_until: it - Notifications::DeadlineReminder::WINDOW).perform_later(exchange) }
    end

    # 予約は数週間先まで残る。その間に交換会が消えることがあり、消えていれば
    # 確かめる締切も知らせる相手も無い。失敗として残さない
    discard_on ActiveJob::DeserializationError

    def perform(exchange)
      # 基準時刻はここで1回だけ読む（docs/spec.md 11.）。予約した時刻ではなく
      # 実際に走った時刻で見る。遅れて走ったなら、遅れた時点の締切が正しい
      Notifications::DeadlineReminder.new(exchange, at: Time.current).deliver
    end
  end
end
