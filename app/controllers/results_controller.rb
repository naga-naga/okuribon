# frozen_string_literal: true

# ギフトコードの平文はここにしか出ない画面が1つある。返却された自分の本の
# コードは、本の詳細画面を持たないためここでしか取り出せない。
# 取得経路そのものは Book#gift_code_for に集約してあり、
# この画面は「並べる対象を絞る」ことだけを受け持つ
class ResultsController < ApplicationController
  include ParticipatingExchange

  before_action :require_login
  before_action :set_participation

  def show
    return render_unpublished unless @exchange.published?(at: requested_at)

    # 冊数と中身の両方を見るので、ここで読み切る。
    # 関係のまま渡すと、冊数を数えるたびに画面から SQL が飛ぶ
    @received = @participation.received_assignments.to_a
    @returned = @participation.returned_assignments.to_a
    # 取得枠は登録した冊数と同数。受け取りが0冊のとき、
    # 枠が無かったのか回ってこなかったのかを画面が言い分けるために要る
    @slots = @participation.books.count

    # 公開前に取れないことは、この手前の 404 が受け持つ
    @result_books = @exchange.result_books
    # 自分が出した本の行き先は、全体の一覧から絞る。別に引くと、
    # 並びと絞り込みが2か所に分かれる
    @given = @result_books.select { it.participation_id == @participation.id }
    @draft_order = @exchange.draft_order.to_a
  end

  private

  # 結果はまだ存在しないので 404 を返す。ただし本文は描く。
  # ここへ来られるのは交換会もフェーズも既に見えている参加者で、実在を伏せる相手ではなく、
  # 素の 404 だと URL を間違えたのか時期が早いのかを言い分けられない。
  # 参加していない人には ParticipatingExchange が先に落ち、素の 404 が返る
  def render_unpublished
    render :unpublished, status: :not_found
  end
end
