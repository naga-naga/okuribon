# frozen_string_literal: true

module Notifications
  # Webhook への投稿を非同期に行う。
  #
  # 投稿を1件1ジョブに分けるのは、フェーズの変わり目を拾う走査（#43）が
  # 交換会を順に見ていくため。走査の中で同期的に送ると、1件の Webhook が
  # 詰まっている間、後ろの交換会の通知がすべて待たされる。
  # リトライも交換会ごとに独立する。
  #
  # 引数に本文をそのまま渡す。ジョブの引数は queue のデータベースに平文で残るので、
  # ギフトコードと招待トークンは載せない（docs/spec.md 11.）。本文にそれらを
  # 混ぜないのは、文面を組む側（#43 #44）の責任にあたる
  class DeliveryJob < ApplicationJob
    # 相手の不調が数分で直ることを見込む。通知が数分遅れて困るものではない一方、
    # 何時間も積み直しても届かないものは届かない
    MAX_ATTEMPTS = 5

    retry_on Webhook::TransientFailure, attempts: MAX_ATTEMPTS, wait: :polynomially_longer do |job, error|
      job.record_failure(error)
    end

    discard_on Webhook::PermanentFailure do |job, error|
      job.record_failure(error)
    end

    # 積んでから実行されるまでの間に交換会が消えることがある。
    # 送り先も本文の意味も無いので、失敗として残さない
    discard_on ActiveJob::DeserializationError

    def perform(exchange, text)
      Webhook.for(exchange)&.deliver(text)
    end

    # 諦めたことをログに残す。通知が来ないことに気付いた人が、
    # 送ろうとしたけれど届かなかったのか、そもそも送っていないのかを見分けられるようにする。
    # 例外のメッセージにはホストまでしか入っていない（Webhook#verify）
    def record_failure(error)
      exchange = arguments.first

      Rails.logger.error("交換会 #{exchange.id} の通知を諦めた: #{error.message}")
    end
  end
end
