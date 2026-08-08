# frozen_string_literal: true

# 本の一覧に出すものを揃える。一覧を開く以外にもこの一覧を描き直す用があるので、
# 読み込みを1か所に置く。別々に書くと、片方にだけ足した絞り込みや並びが
# もう片方から消える
module BookListing
  extend ActiveSupport::Concern

  private

  # @exchange と @participation は各コントローラが先に決めておく。
  # 参加から引かなければ、参加していない交換会の本まで読めてしまう
  def load_book_listing
    # 冊数の表示と空の判定にも同じ本を使うので、その場で読み込む。
    # 関連のままだと、並べる前に COUNT と EXISTS が別々に飛ぶ
    @books = @exchange.books.includes(:registrant).order(:created_at, :id).load

    # 見出しの「N冊 ／ M人」に使う。冊数だけでは、まだ1冊も登録していない人が
    # どれだけ残っているかが分からない
    @participant_count = @exchange.participations.count

    # 絞り込みは URL に残す。開き直しても同じ並びで戻れる。
    # 押せる口は2つしかないので、知らない値は全件に倒す
    @mine_only = params[:filter] == 'mine'
  end
end
