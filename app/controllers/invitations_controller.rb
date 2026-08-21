# frozen_string_literal: true

# 未参加の人と未ログインの人が最初に見る画面なので、ログインを求めない
class InvitationsController < ApplicationController
  def show
    # 引けなければ 404。トークンが正しくないことと交換会が無いことを区別しない
    @exchange = Exchange.find_by!(invite_token: params.expect(:token))

    # ログインを挟んでもこの画面へ戻す。覚えるのはサーバーが見たパスだけで、
    # 招待URLはこの GET でしか渡ってこない
    store_return_to unless logged_in?
  end
end
