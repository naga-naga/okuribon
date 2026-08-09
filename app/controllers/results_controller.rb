# frozen_string_literal: true

# 結果画面。交換会のクライマックスで、受け取った本とギフトコードを開く場所。
#
# ギフトコードの平文はここにしか出ない画面が1つある。返却された自分の本の
# コードは、本の詳細画面を持たないため（docs/spec.md 6.3）ここ以外に
# 取り出し口が無い。取得経路そのものは Book#gift_code_for に集約してあり、
# この画面は「並べる対象を絞る」ことだけを受け持つ
class ResultsController < ApplicationController
  before_action :require_login

  # 交換会は参加から引く。参加していなければ見つからない。
  # 本の一覧や交換会トップと同じ入口にして、画面ごとに条件を手書きしない
  def show
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:exchange_id))
    @exchange = @participation.exchange

    return render_unpublished unless @exchange.published?(at: requested_at)

    # 冊数と中身の両方を見るので、ここで読み切る。
    # 関係のまま渡すと、冊数を数えるたびに画面から SQL が飛ぶ
    @received = @participation.received_assignments.to_a
    @returned = @participation.returned_assignments.to_a
    # 取得枠は登録した冊数と同数（docs/spec.md 3.）。受け取りが0冊のとき、
    # 枠が無かったのか回ってこなかったのかを画面が言い分けるために要る
    @slots = @participation.books.count
  end

  private

  # 結果はまだ存在しないので 404 を返す。ただし本文は描く。
  # 素の 404 だと、参加者が自分の交換会で行き止まりに当たり、URL を間違えたのか
  # 時期が早いのかを区別できない。実在を伏せる必要があるのは主催者専用の画面だけで
  # （docs/spec.md 8.）、ここへ来られるのは交換会もフェーズも既に見えている参加者。
  # 参加していない人には find_by! が先に落ち、素の 404 が返る
  def render_unpublished
    render :unpublished, status: :not_found
  end
end
