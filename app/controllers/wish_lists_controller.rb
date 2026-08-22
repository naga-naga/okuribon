# frozen_string_literal: true

# 追加と削除はその場で1冊ずつ保存し、ここでは順序だけをまとめて受け取る
class WishListsController < ApplicationController
  include BookListing
  include ParticipatingExchange

  before_action :require_login
  before_action :set_participation

  # PhaseGuard は重ねない。フェーズの検証も行ロックも順位の再採番も
  # Participation に集約してあり、追加・削除・並べ替えの3経路が同じ検証を通る。
  # 送られた順序もそのまま順位にはせず、モデル側で1から振り直す
  def update
    @participation.reorder_wishes!(params.expect(book_ids: []), at: requested_at)

    render_listing
  end
end
