# frozen_string_literal: true

class SessionsController < ApplicationController
  include PendingParticipation

  # ログイン画面。root も兼ねる。
  # 交換会一覧（#18）が入ったら、ログイン済みの着地はそちらへ移す
  def new
    # 参加の途中で送られてきた人には、何のためのログインかを見せる
    @pending_participation = pending_participation
  end

  # OAuth のコールバック。認証情報は OmniAuth のミドルウェアが env に載せる
  def create
    # log_in がセッションを作り直すので、預かったものはその前に取り出す
    destination = pop_return_to
    pending = pop_pending_participation

    log_in(User.from_omniauth(request.env['omniauth.auth']))

    return redirect_to destination if pending.nil?

    # 参加できたかどうかによらず招待画面へ戻す。
    # 参加できなかった理由は、あの画面がフェーズを見て説明する
    redirect_to invitation_path(pending.invite_token),
                notice: (t('participation.flash.joined') if join_pending(pending))
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
