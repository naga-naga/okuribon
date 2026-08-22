# frozen_string_literal: true

class InviteTokensController < ApplicationController
  before_action :require_login

  # 主催した交換会からしか引かず、主催者以外には 404 で実在を伏せる。
  # フェーズでは閉じない。締切後に配り直しても、着地画面が参加を断る
  def update
    exchange = current_user.owned_exchanges.find(params.expect(:exchange_id))
    exchange.reissue_invite_token!

    redirect_to exchange_management_path(exchange),
                notice: t('management.flash.invite_token_reissued')
  end
end
