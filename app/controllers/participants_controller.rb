# frozen_string_literal: true

# 除外の条件は本人の辞退と同じなので、判定は Exchange#remove_participant! に任せる
class ParticipantsController < ApplicationController
  before_action :require_login

  # 主催した交換会からしか引かず、主催者以外には 404 で実在を伏せる。
  # 参加も交換会の下から引く。id だけで引くと、番号を数えるだけで
  # 他の交換会の参加を消せてしまう
  def destroy
    exchange = current_user.owned_exchanges.find(params.expect(:exchange_id))
    participation = exchange.participations.find(params.expect(:id))

    # 名前は消す前に控える。フラッシュに出すのはこの人を外したという事実で、
    # 参加が消えたあとに引き直せる保証はない
    name = participation.user.display_name
    exchange.remove_participant!(participation.user, at: requested_at)

    redirect_to exchange_management_path(exchange),
                notice: t('management.flash.participant_excluded', name:)
  end
end
