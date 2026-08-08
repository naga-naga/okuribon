# frozen_string_literal: true

class Participation < ApplicationRecord
  # 並べ替えに渡された本が、現在の希望リストと食い違うときに投げる。
  # 食い違うのは別のタブで追加・削除したときなので、届いた並びを正として
  # 差分を反映すると、そちらの変更が黙って消える
  class WishListMismatch < StandardError
    def initialize(message = I18n.t('participation.wish_list_mismatch'))
      super
    end
  end

  belongs_to :exchange
  belongs_to :user

  has_many :books, dependent: :destroy
  # 希望リストは順序が意味を持つ。読む側それぞれに order を書かせると、
  # 書き忘れた1か所だけが違う並びを見ることになる
  has_many :wishes, -> { order(:position) }, dependent: :destroy, inverse_of: :participation
  has_many :assignments, dependent: :destroy

  # 希望リストの末尾に1冊足す。
  # 二重の希望は一意インデックスに任せる。先に exists? で調べても、その隙に入られると防げない。
  # 二度押しで例外にせず同じ希望を返すのは、Exchange#join! と同じ理由
  def add_wish!(book, at:)
    verify_wish_writable!(at:)

    with_lock do
      wishes.create_or_find_by!(book:) { |wish| wish.position = wishes.maximum(:position).to_i + 1 }
    end
  end

  # 希望リストから1冊外す。希望していない本を渡されても何もしない。
  # 二度押しや、別のタブで消したあとの再送信で落とすようなことではない
  def remove_wish!(book, at:)
    verify_wish_writable!(at:)

    with_lock do
      wish = wishes.find_by(book:)
      next if wish.nil?

      wish.destroy!
      renumber_wishes
    end
  end

  # 希望リストを渡された順に並べ替える。追加も削除もしない。
  # 集合が一致することを求めるのは、ここが楽観ロックを兼ねるため。
  # 一致しなければ、その並びは今の希望リストを見て作られたものではない
  def reorder_wishes!(book_ids, at:)
    verify_wish_writable!(at:)

    # 並びはフォームから来るので、値は文字列で届く
    ordered_ids = Array(book_ids).map(&:to_i)

    with_lock do
      wishes_by_book_id = wishes.reload.index_by(&:book_id)
      # 集合ではなく並べた数ごと突き合わせる。Set にすると重複が潰れ、[A, A, B] が
      # [A, B] と同じものとして通る。A に順位を2度振ることになり、1番が空く
      raise WishListMismatch unless ordered_ids.sort == wishes_by_book_id.keys.sort

      ordered_ids.each_with_index do |book_id, index|
        wishes_by_book_id.fetch(book_id).update!(position: index + 1)
      end
    end
  end

  private

  # 順位は1から始まる連番に保つ。穴が空いたままだと、次に足した1冊の順位が飛び、
  # 画面に出す順位とリストの何番目かが食い違う。
  # 順位の一意制約は遅延させてあるので、退避用の値を経由せずそのまま書き換えてよい
  def renumber_wishes
    wishes.reload.each_with_index do |wish, index|
      wish.update!(position: index + 1)
    end
  end

  # フェーズの判定はコントローラに置かない。希望リストの変更の入口は
  # 追加・削除・並べ替えの3つあり、それぞれに条件を手書きすると口ごとに食い違う
  def verify_wish_writable!(at:)
    return if exchange.writable?(:wish, at:)

    raise Exchange::PhaseViolation.new(exchange, :wish, at:)
  end
end
