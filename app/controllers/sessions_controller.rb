# frozen_string_literal: true

class SessionsController < ApplicationController
  include PendingParticipation

  # ログイン画面。ログイン済みなら追い返す。以前は開けるようにしていたが、
  # それはログアウトの導線がここにしかなく、追い返すと抜けられなくなるため
  # だった。共通ヘッダーが全画面でログアウトを持つので、その理由は無くなった
  def new
    return redirect_to root_path if logged_in?

    # 参加の途中で送られてきた人には、何のためのログインかを見せる
    @pending_participation = pending_participation
  end

  # 認証情報は OmniAuth のミドルウェアが env に載せる
  def create
    # log_in がセッションを作り直すので、保存したものはその前に取り出す
    destination = pop_return_to
    pending = pop_pending_participation

    log_in(User.from_omniauth(request.env['omniauth.auth']))

    return redirect_to destination if pending.nil?

    # 参加できたなら交換会トップへ渡す。ログインを挟まない経路と着地を揃える。
    # できなかったときだけ招待URLの着地画面へ戻し、その理由を
    # 着地画面にフェーズから説明させる
    return redirect_to invitation_path(pending.invite_token) unless join_pending(pending)

    redirect_to exchange_path(pending), notice: t('participation.flash.joined')
  end

  def destroy
    log_out

    redirect_to login_path
  end

  private

  # Google の同意画面にいる間に締切をまたぐことがある。
  # 参加は見送るが、ログインまで失敗させると利用者には何が起きたのか分からない
  def join_pending(exchange)
    exchange.join!(current_user, at: requested_at)
  rescue Exchange::PhaseViolation
    nil
  end
end
