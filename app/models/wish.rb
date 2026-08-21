# frozen_string_literal: true

class Wish < ApplicationRecord
  belongs_to :participation
  belongs_to :book

  # 順位は画面から来る値ではないが、組み立てを間違えたときに 500 で気付くことになる
  validates :position, presence: true

  # 順位の重複と二重希望は DB の制約が受け持つ。前者は並べ替えの途中で必ず重複するため
  # バリデーションでは見られず、後者は先に exists? で調べてもその隙に入られる。
  # ここに置くのは、時刻にも他のレコードの状態にも左右されない2つだけにする
  validate :book_not_own
  validate :book_in_same_exchange

  private

  # 自分の本を希望に入れられると、選んだのに絶対に当たらない枠を1つ抱えることになる。
  # 保存前の参加と本は id を持たない。nil どうしを突き合わせると、別々に作った
  # ものが同じ参加のものに見える。id が揃うのは保存後で、そのときに改めて通る
  def book_not_own
    return if book.nil? || participation_id.nil?
    return if book.participation_id != participation_id

    errors.add(:book, :own_book)
  end

  def book_in_same_exchange
    return if participation.nil? || book&.participation.nil?
    return if participation.exchange_id.nil? || book.participation.exchange_id.nil?
    return if book.participation.exchange_id == participation.exchange_id

    errors.add(:book, :other_exchange)
  end
end
