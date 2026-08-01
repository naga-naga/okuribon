# frozen_string_literal: true

# フェーズが許さない書き込みを、サーバー側で一律に止める。
# 各コントローラは guard_phase で操作名を宣言し、current_exchange を返すだけでよい。
# フェーズの条件そのものは Exchange::WRITABLE_PHASES にあり、ここには持たない
module PhaseGuard
  extend ActiveSupport::Concern

  class_methods do
    # キーワード引数は before_action にそのまま渡す（only: / except: など）。
    # 読み取りは全フェーズで開いているため、対象は書き込みのアクションに絞る
    def guard_phase(operation, **)
      before_action(**) { verify_writable_phase(operation) }
    end
  end

  private

  # 基準時刻はサーバーがリクエストを受けた時刻。リクエストから来たフェーズや
  # 時刻は読まない。クライアントの時計を信用すると、締切を過ぎた書き込みが通る。
  # 判定とメッセージで同じ時刻を使い、境界ちょうどで両者がずれないようにする
  def verify_writable_phase(operation)
    at = requested_at
    return if current_exchange.writable?(operation, at:)

    raise Exchange::PhaseViolation.new(current_exchange, operation, at:)
  end

  # 対象の交換会は各コントローラが返す。
  # 未定義のまま guard_phase を書くと、拒否ではなくここで落ちる
  def current_exchange
    raise NotImplementedError, "#{self.class} に current_exchange を実装すること"
  end
end
