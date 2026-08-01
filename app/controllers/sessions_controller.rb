# frozen_string_literal: true

class SessionsController < ApplicationController
  # OAuth のコールバック。認証情報は OmniAuth のミドルウェアが env に載せる
  def create
    User.from_omniauth(request.env['omniauth.auth'])

    # セッションへの保存と元の画面への復帰は #13 で入る
    redirect_to '/'
  end
end
