# frozen_string_literal: true

class SessionsController < ApplicationController
  # ログイン画面。root も兼ねる。
  # 交換会一覧（#18）が入ったら、ログイン済みの着地はそちらへ移す
  def new; end

  # OAuth のコールバック。認証情報は OmniAuth のミドルウェアが env に載せる
  def create
    # log_in がセッションを作り直すので、戻り先はその前に取り出す
    destination = pop_return_to

    log_in(User.from_omniauth(request.env['omniauth.auth']))

    redirect_to destination
  end

  def destroy
    log_out

    redirect_to login_path
  end
end
