# frozen_string_literal: true

# 希望リストへの1冊の出し入れ。追加と削除はその場で保存し、
# 並べ替えは順序だけをまとめて送る（docs/spec.md 6.2 / #27）
class WishesController < ApplicationController
  include BookListing

  before_action :require_login
  before_action :set_participation
  before_action :set_book

  # PhaseGuard は重ねない。フェーズの検証も行ロックも順位の再採番も
  # Participation の中にある（#24）。希望リストを変える口は追加・削除・並べ替えの
  # 3つあり、条件をコントローラにも書くと、片方だけ直したときに口ごとに食い違う
  def create
    @participation.add_wish!(@book, at: requested_at)

    render_listing
  rescue ActiveRecord::RecordInvalid => e
    # 自分の本を希望に入れようとしたとき。ボタンを出さないので画面からは来ないが、
    # 直に叩かれたときに 500 で落とすようなことではない
    deny_wish(e.record)
  end

  def destroy
    @participation.remove_wish!(@book, at: requested_at)

    render_listing
  end

  private

  # 交換会は参加から引く。参加していなければ見つからない。
  # 本の一覧と同じ入口にする。読み取りと書き込みで分けると、片方だけ緩む
  def set_participation
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:exchange_id))
    @exchange = @participation.exchange
  end

  # 本も交換会から引く。別の交換会の本を渡されても見つからない。
  # 希望リストが交換会をまたぐと、取得枠の勘定が成り立たない
  def set_book
    @book = @exchange.books.find(params.expect(:book_id))
  end

  # 1冊外すと後ろの順位がすべて繰り上がる。押したカードだけを差し替えると、
  # 繰り上がった他のカードの順位が古いまま残る。
  # 差し替えるのは一覧と希望リストの中身で、開閉の状態を持つシートの外枠は含めない
  def render_listing
    load_book_listing

    respond_to do |format|
      format.turbo_stream { render :listing }
      # JavaScript が無くても通る道を残す。絞り込みは URL に残っているので持ち回す
      format.html { redirect_to exchange_books_path(@exchange, filter: params[:filter].presence) }
    end
  end

  def deny_wish(wish)
    render 'errors/denied', status: :unprocessable_content,
                            locals: { message: wish.errors.full_messages.to_sentence }
  end
end
