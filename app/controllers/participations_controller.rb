# frozen_string_literal: true

# 交換会の id ではなく招待トークンで引く。
# id で受けると、番号を数えるだけで招待されていない交換会に参加できてしまう
class ParticipationsController < ApplicationController
  include PendingParticipation

  # 参加はログイン前でも受ける。押した事実を保存してからログインへ送るため、
  # ここで止めると意図が残らない。辞退にその往復は要らない
  before_action :require_login, only: :destroy

  def create
    return send_to_login(exchange) unless logged_in?

    # フェーズの検証は Exchange#join! の中にある。
    # 拒否は PhaseViolation になり、応答は ApplicationController が組み立てる
    exchange.join!(current_user, at: requested_at)

    # 招待URL着地画面は未参加の人のための画面なので、参加が済んだらトップへ渡す
    redirect_to exchange_path(exchange), notice: t('participation.flash.joined')
  end

  def destroy
    exchange.remove_participant!(current_user, at: requested_at)

    redirect_to invitation_path(exchange.invite_token), notice: t('participation.flash.withdrawn')
  end

  private

  # 引けなければ 404。トークンが正しくないことと交換会が無いことを区別しない
  def exchange
    @exchange ||= Exchange.find_by!(invite_token: params.expect(:token))
  end

  # 認証開始は POST に限るため、ここから OAuth へ直接つなぐことはできない。
  # 押した事実だけを保存してログイン画面へ送り、戻ったところで参加を確定させる
  def send_to_login(exchange)
    store_pending_participation(exchange)

    redirect_to login_path
  end
end
