# frozen_string_literal: true

# 主催者管理画面。参加者の状況を把握し、交換会の設定と進行を操作する場所。
# この画面が骨格で、招待URL（#37）・日時の変更（#38）・参加者の除外（#39）・
# マッチングの実行（#31）がここへ足されていく
class ManagementsController < ApplicationController
  before_action :require_login

  # 主催した交換会からしか引かない。見つからなければ 404 になり、
  # 主催者以外には交換会の実在そのものを伏せる。403 を返すと、
  # 招待されていない交換会が在ることを URL を試すだけで確かめられてしまう。
  # フェーズでは閉じない。締切を延ばすのも実行するのもこの画面の仕事なので、
  # 特定のフェーズで閉じると主催者が自分の交換会に入れなくなる
  def show
    @exchange = current_user.owned_exchanges.find(params.expect(:exchange_id))
    # 冊数は SQL で数える。Book を読み込むと、数を出すだけの画面へ
    # 暗号化されたギフトコードまで運ばれてくる
    @participations = @exchange.participations
                               .with_counts
                               .includes(:user)
                               .order(:created_at, :id)
    @imbalance = imbalance
    @matching_summary = matching_summary
  end

  private

  # 偏りの警告を出すのは、本を登録できるあいだだけ（docs/spec.md 6.8）。
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
