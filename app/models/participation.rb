# frozen_string_literal: true

class Participation < ApplicationRecord
  # 並べ替えの並びが現在の希望リストと食い違うのは、別のタブで追加・削除したとき。
  # 届いた並びを正として差分を反映すると、そちらの変更が黙って消える
  class WishListMismatch < StandardError
    attr_reader :exchange

    def initialize(exchange)
      @exchange = exchange

      super(I18n.t('participation.wish_list_mismatch'))
    end
  end

  belongs_to :exchange
  belongs_to :user

  # 冊数だけが要る画面で Book を読み込むと、暗号化されたギフトコードまで
  # 一緒に取得してしまうため、数だけを SQL で受け取る。
  # DISTINCT を外せない。Book と Wish を同時に外部結合すると行が掛け合わさり、
  # 2冊×3希望がどちらも6件と重複して数えられる
  scope :with_counts, lambda {
    left_joins(:books, :wishes)
      .select('participations.*',
              'COUNT(DISTINCT books.id) AS books_count',
              'COUNT(DISTINCT wishes.id) AS wishes_count')
      .group('participations.id')
  }

  has_many :books, dependent: :destroy
  # 希望リストは順序が意味を持つ。読む側それぞれに order を書かせると、
  # 書き忘れた1か所だけが違う並びを見ることになる
  has_many :wishes, -> { order(:position) }, dependent: :destroy, inverse_of: :participation
  has_many :assignments, dependent: :destroy

  # 返却は誰にも渡せなかった本が登録者へ戻ることなので、
  # 受け取りには数えない（Book#recipient? と同じ扱い）。
  # ドラフトで取れた順に並べ、余り物の割当（巡が nil）は最後に置く。
  # NULLS LAST は明示する。省くと、NULL をどちらの端へ置くかが DBMS の既定任せになり、
  # 並び順が暗黙の前提の上に乗る
  def received_assignments
    assignments.where(returned: false)
               .order(Assignment.arel_table[:round].asc.nulls_last, :id)
               .includes(book: [:registrant, :assignment, :exchange])
  end

  # マッチングは返却の割当を登録者の参加に紐づけるので、
  # 受け取った本と同じ関連から引ける。
  # 本の詳細画面を持たないため、誰にも渡らなかったギフトコードを取得する経路はここしかない
  def returned_assignments
    assignments.where(returned: true).order(:id)
               .includes(book: [:registrant, :assignment, :exchange])
  end

  # 二重の希望は一意インデックスに任せる。先に exists? で調べても、その隙に入られると防げない。
  # 二度押しで例外にせず同じ希望を返すのは、Exchange#join! と同じ理由
  def add_wish!(book, at:)
    verify_wish_writable!(at:)

    with_lock do
      wishes.create_or_find_by!(book:) { |wish| wish.position = wishes.maximum(:position).to_i + 1 }
    end
  end

  # 希望していない本を渡されても何もしない。
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
      raise WishListMismatch, exchange unless ordered_ids.sort == wishes_by_book_id.keys.sort

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
  # 追加・削除・並べ替えの3つあり、それぞれに条件を手書きすると経路ごとに食い違う
  def verify_wish_writable!(at:)
    return if exchange.writable?(:wish, at:)

    raise Exchange::PhaseViolation.new(exchange, :wish, at:)
  end
end
