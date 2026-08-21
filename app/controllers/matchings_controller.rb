# frozen_string_literal: true

# 実行そのものは Matching::Execution が持つ。行ロックもフェーズの検証も
# 二重実行の拒否もあちらの内側にあるので、ここでは主催者かどうかだけを見る
class MatchingsController < ApplicationController
  before_action :require_login
  # 主催した交換会からしか引かない。管理画面と同じ理由で、
  # 主催者以外には 404 を返して交換会の実在そのものを伏せる
  before_action :set_exchange

  def new
    # 締切前や実行済みのときは、確認画面も開かない。通らない道を先に見せると、
    # 押せると思わせたまま最後に断ることになる。判定は交換会ページが実行への
    # 導線を出すかどうかと同じ述語から引く。別々に書くと、押しても断られる導線が残る
    raise Exchange::PhaseViolation.new(@exchange, :matching, at: requested_at) unless executable?

    @summary = Exchanges::MatchingSummary.new(@exchange.participations.with_counts).call
  end

  def create
    Matching::Execution.new(exchange: @exchange, at: requested_at).call

    # 行き先は結果画面ではなく管理画面にする。押したのは主催者の操作で、
    # まず確かめたいのは実行が通ったこと。管理画面は実行日時を残すので、
    # そこで確かめられる。結果は交換会トップから、参加者として見に行く
    redirect_to exchange_management_path(@exchange),
                notice: t('management.flash.matching_executed')
  end

  private

  def set_exchange
    @exchange = current_user.owned_exchanges.find(params.expect(:exchange_id))
  end

  def executable?
    @exchange.matching_executable?(current_user, at: requested_at)
  end
end
