# frozen_string_literal: true

# 希望リスト全体の並べ替え。追加と削除はその場で1冊ずつ保存し、
# ここでは順序だけをまとめて受け取る（docs/spec.md 6.2 / #27）
class WishListsController < ApplicationController
  include BookListing

  before_action :require_login
  before_action :set_participation

  # PhaseGuard は重ねない。フェーズの検証も行ロックも順位の再採番も
  # Participation の中にある（#24）。希望リストを変える口は追加・削除・並べ替えの
  # 3つあり、条件をコントローラにも書くと、片方だけ直したときに口ごとに食い違う。
  # 送られた順序もそのまま順位にはせず、モデル側で1から振り直す
  def update
    @participation.reorder_wishes!(params.expect(book_ids: []), at: requested_at)

    render_listing
  end

  private

  # 交換会は参加から引く。参加していなければ見つからない。
  # 本の一覧と同じ入口にする。読み取りと書き込みで分けると、片方だけ緩む
  def set_participation
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:exchange_id))
    @exchange = @participation.exchange
  end
end
