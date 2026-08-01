# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # フェーズによる拒否の応答はここだけで組み立てる。書き込み口ごとに書かない
  rescue_from Exchange::PhaseViolation, with: :deny_by_phase

  private

  # 403 ではなく 409 を返す。リクエストの形も認可も正しく、
  # 交換会の現在のフェーズだけが操作を許していないため。
  # Turbo は 4xx の本文を描画するので、画面にもメッセージが出る
  def deny_by_phase(error)
    render 'errors/phase_violation', status: :conflict, locals: { message: error.message }
  end
end
