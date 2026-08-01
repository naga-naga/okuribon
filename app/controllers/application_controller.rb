# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # フェーズによる拒否の応答はここだけで組み立てる。書き込み口ごとに書かない
  rescue_from Exchange::PhaseViolation, with: :deny_by_phase

  # コールバックの先頭で確定させる。遅延させると、実際に読むのは
  # 途中の before_action の中になり、名前が指す時刻とずれる
  before_action :requested_at

  helper_method :requested_at

  private

  # フェーズ判定の基準時刻。リクエストを受けた時刻を1回だけ読み、以降は回す。
  # 読むたびに現在時刻を取ると、締切をまたいだ瞬間に、同じ画面の中で
  # ヘッダーと本文のフェーズが食い違う
  def requested_at
    @requested_at ||= Time.current
  end

  # 403 ではなく 409 を返す。リクエストの形も認可も正しく、
  # 交換会の現在のフェーズだけが操作を許していないため。
  # Turbo は 4xx の本文を描画するので、画面にもメッセージが出る
  def deny_by_phase(error)
    render 'errors/phase_violation', status: :conflict, locals: { message: error.message }
  end
end
