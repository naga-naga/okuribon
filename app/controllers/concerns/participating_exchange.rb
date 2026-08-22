# frozen_string_literal: true

# 参加を引いて交換会を辿る。参加していなければ見つからず、
# 404 になって交換会の実在を伏せる。読み取りと書き込みで入口を分けない
module ParticipatingExchange
  extend ActiveSupport::Concern

  private

  # ネストされたルートは :exchange_id、交換会そのものを開くルートは :id と、
  # ルートのキーだけが違う。取り出しは呼ぶ側に任せ、引き方はここに1つだけ置く
  def set_participation(exchange_id = params.expect(:exchange_id))
    @participation = current_user.participations.find_by!(exchange_id:)
    @exchange = @participation.exchange
  end
end
