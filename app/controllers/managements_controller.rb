# frozen_string_literal: true

class ManagementsController < ApplicationController
  before_action :require_login

  # 主催した交換会からしか引かず、主催者以外には 404 で実在を伏せる。
  # フェーズでは閉じない。締切を延ばすのも実行するのもこの画面の仕事なので、
  # 特定のフェーズで閉じると主催者が自分の交換会に入れなくなる
  def show
    @exchange = current_user.owned_exchanges.find(params.expect(:exchange_id))
    @participations = @exchange.participations
                               .with_counts
                               .includes(:user)
                               .order(:created_at, :id)
    @imbalance = imbalance
    @matching_summary = matching_summary
  end

  private

  # 偏りの警告は、本を登録できるあいだに限って出す。
  # 締切を過ぎてからでは、追加登録を促す先がもう無い。求めているのは
  # 「まだ冊数を動かせるフェーズか」そのものなので、日時の比較を書き足さず
  # フェーズの表から引く。読み込み済みの参加を渡して、冊数を数え直させない
  def imbalance
    return nil unless @exchange.writable?(:book, at: requested_at)

    Exchanges::BookImbalance.new(@participations).call
  end

  # 実行の前に確かめることを挙げるための数。要るのは実行できるあいだだけで、
  # 締切前は打つ手がまだ登録と希望提出のほうにあり、実行後は変えようがない。
  # 判定は Matching::Execution が実行時に見るものと同じ表から引く。
  # 読み込み済みの参加を渡して、冊数を数え直させない
  def matching_summary
    return nil unless @exchange.writable?(:matching, at: requested_at)

    Exchanges::MatchingSummary.new(@participations).call
  end
end
