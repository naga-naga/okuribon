# frozen_string_literal: true

# 招待URLからの参加。交換会の id ではなく招待トークンで引く。
# id で受けると、番号を数えるだけで招待されていない交換会に参加できてしまう
class ParticipationsController < ApplicationController
  include PendingParticipation

  def create
    # 引けなければ 404。トークンが正しくないことと交換会が無いことを区別しない
    exchange = Exchange.find_by!(invite_token: params.expect(:token))

    return send_to_login(exchange) unless logged_in?

    # フェーズの検証は Exchange#join! の中にある。
    # 拒否は PhaseViolation になり、応答は ApplicationController が組み立てる
    exchange.join!(current_user, at: requested_at)

    # 交換会トップ（#19）が入ったら、そちらへ送る
    redirect_to invitation_path(exchange.invite_token), notice: t('participation.flash.joined')
  end

  private

  # 認証開始は POST に限るため、ここから OAuth へ直接つなぐことはできない。
  # 押した事実だけを預けてログイン画面へ送り、戻ったところで参加を確定させる
  def send_to_login(exchange)
    store_pending_participation(exchange)

    redirect_to login_path
  end
end
