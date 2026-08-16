# frozen_string_literal: true

module Notifications
  # 1つの交換会がフェーズの変わり目に来たかを確かめ、来ていれば知らせる。
  #
  # フェーズが切り替わる時刻は交換会の日時カラムそのものなので、その時刻を予約して
  # 確認しに行く。定期的に全件を見に回るより、境目を直接指せる。
  #
  # 予約は取り消さない。主催者が日時を動かしたら新しい時刻を積み足すだけにする。
  # 古い予約が残っても、Notifications::PhaseChange が実行時にフェーズを導出して
  # 記録と突き合わせるので、空振りするか正しい通知を出すかのどちらかにしかならない。
  # 予約は「この時刻に確認しに来て」という合図で、正しさはこのジョブの側が持つ
  class PhaseCheckJob < ApplicationJob
    # 予約する時刻を持つカラム。マッチング実行日時が入っているのは、結果公開だけが
    # 日時で決まらないため。主催者がボタンを押した時刻はもう過ぎているので、
    # 予約した時点で待たずに走る
    BOUNDARY_COLUMNS = [
      :registration_starts_at, :registration_ends_at, :wish_ends_at, :matched_at,
    ].freeze

    # 変わった時刻だけを予約する。全部を積み直すと、日時を1つ動かすたびに
    # 動かしていない境目の予約まで増える
    def self.reserve(exchange, columns)
      columns.each do |column|
        at = exchange.read_attribute(column)
        next if at.nil?

        set(wait_until: at).perform_later(exchange)
      end
    end

    # 予約は数週間先まで残る。その間に交換会が消えることがあり、消えていれば
    # 確かめるフェーズも知らせる相手も無い。失敗として残さない
    discard_on ActiveJob::DeserializationError

    def perform(exchange)
      # 基準時刻はここで1回だけ読む（docs/spec.md 11.）。予約した時刻ではなく
      # 実際に走った時刻で見る。遅れて走ったなら、遅れた時点のフェーズが正しい
      Notifications::PhaseChange.new(exchange, at: Time.current).deliver
    end
  end
end
