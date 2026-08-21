# frozen_string_literal: true

# 追加と削除はその場で保存し、並べ替えは順序だけをまとめて送る
class WishesController < ApplicationController
  include BookListing
  include ParticipatingExchange

  before_action :require_login
  before_action :set_participation
  before_action :set_book

  # PhaseGuard は重ねない。フェーズの検証も行ロックも順位の再採番も
  # Participation の中にある。希望リストを変える口は追加・削除・並べ替えの
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

  # 本も交換会から引く。別の交換会の本を渡されても見つからない。
  # 希望リストが交換会をまたぐと、取得枠の勘定が成り立たない
  def set_book
    @book = @exchange.books.find(params.expect(:book_id))
  end

  # こちらは例外ではなく検証の失敗なので、戻り先は引いてきた交換会から渡す
  def deny_wish(wish)
    render 'errors/denied', status: :unprocessable_content,
                            locals: { message: wish.errors.full_messages.to_sentence,
                                      exchange: @exchange }
  end
end
