# frozen_string_literal: true

class Wish < ApplicationRecord
  belongs_to :participation
  belongs_to :book

  # 順位と二重希望は DB の制約が受け持つ。前者は並べ替えの途中で必ず重複するため
  # バリデーションでは見られず、後者は先に exists? で調べてもその隙に入られる。
  # ここに置くのは、時刻にも他のレコードの状態にも左右されない2つだけにする
  validate :book_not_own
  validate :book_in_same_exchange

  private

  # 自分が登録した本は受け取れない（docs/spec.md 3. 交換の仕組み）。
  # 希望に入れられると、選んだのに絶対に当たらない枠を1つ抱えることになる
  def book_not_own
    return if participation.nil? || book.nil?
    return if book.participation_id != participation_id

    errors.add(:book, :own_book)
  end

  def book_in_same_exchange
    return if participation.nil? || book.nil?
    return if book.participation.exchange_id == participation.exchange_id

    errors.add(:book, :other_exchange)
  end
end
