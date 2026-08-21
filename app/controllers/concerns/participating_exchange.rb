# frozen_string_literal: true

# 交換会そのものを引いて権限を後から見るのではなく、参加を引いて交換会を辿る。
# 参加していなければ見つからず、403 ではなく 404 になる。403 を返すと、
# 招待されていない交換会の実在が URL を試すだけで分かる。
#
# 読み取りと書き込みで入口を分けない。経路ごとに条件を手書きすると、
# 経路を足したときに片方だけ緩む
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
