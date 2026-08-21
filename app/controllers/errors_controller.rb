# frozen_string_literal: true

# exceptions_app が PATH_INFO をステータスに書き換えてここへ流す。
#
# ログインは求めない。求めると、未ログインの人が受け取る 404 が
# ログイン画面へのリダイレクトに変わり、どこで分岐したかで実在が漏れる。
# 交換会も引かない。エラー画面が対象を引き当てられると、
# 引けたかどうかが本文に出てしまう
class ErrorsController < ApplicationController
  def show
    # パスはルーティングで '/400' '/404' '/422' に限られている（config/application.rb）。
    # 応答のステータスは、ここへ流れてきた元の例外のものをそのまま返す
    @status = request.path.delete_prefix('/').to_i

    render :show, status: @status
  end
end
