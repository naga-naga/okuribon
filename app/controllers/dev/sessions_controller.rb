# frozen_string_literal: true

module Dev
  # 開発用の裏口ログイン。OAuth を通さずに seed が作った利用者へ入れ替わる。
  #
  # seed の利用者は Google のアカウントを持たないため、本来の経路では入れない。
  # 5フェーズと状態バリエーションは「誰として見るか」で意味が変わるので、
  # 入れ替われないと作ったデータの大半が確かめられない。
  class SessionsController < ApplicationController
    before_action :block_outside_local

    def new
      # 作った順に並べる。名前で並べ替えると、シナリオの主役が埋もれる
      @users = User.order(:id)
    end

    def create
      log_in(User.find(params.expect(:user_id)))

      redirect_to root_path
    end

    private

    # ルーティングは local のときだけ描くので、本番にこの経路は無い。
    # それでも塞ぐのは、環境の取り違えで描かれたときに素通りさせないため。
    # 403 ではなく 404 を返し、口があること自体を伏せる
    def block_outside_local
      head :not_found unless Rails.env.local?
    end
  end
end
