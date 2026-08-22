# frozen_string_literal: true

# exceptions_app が PATH_INFO をステータスに書き換えてここへ流す。
#
# ログインを求めず、交換会も引き当てない。
# どちらも、応答の分岐から実在が漏れる経路になる
class ErrorsController < ApplicationController
  def show
    # パスはルーティングで '/400' '/404' '/422' に限られている（config/application.rb）。
    # 応答のステータスは、ここへ流れてきた元の例外のものをそのまま返す
    @status = request.path.delete_prefix('/').to_i

    render :show, status: @status
  end
end
