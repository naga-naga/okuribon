# frozen_string_literal: true

# 認証開始は POST に限られ、しかも OmniAuth のミドルウェアが横取りするため、
# 「ログインして参加する」を押した事実はコントローラからは一度も見えない。
# 押した時にここへ保存し、認証から戻ったところで取り出す。
#
# 画面を開いた時点では保存しない。開いただけで立ち去った人まで、
# 後日どこかでログインした拍子に参加させてしまうため
module PendingParticipation
  extend ActiveSupport::Concern

  private

  def store_pending_participation(exchange)
    session[:pending_participation_token] = exchange.invite_token
  end

  # 交換会が消えていれば nil になる。保存したあとに消えても画面は壊さない
  def pending_participation
    token = session[:pending_participation_token]
    return if token.blank?

    Exchange.find_by(invite_token: token)
  end

  # 一度使ったら消す。残すと、次のログインで身に覚えのない参加が作られる
  def pop_pending_participation
    pending_participation.tap { session.delete(:pending_participation_token) }
  end
end
