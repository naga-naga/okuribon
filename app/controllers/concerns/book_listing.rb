# frozen_string_literal: true

# 本の一覧に出すものを揃える。一覧を開くときと、希望を追加・削除したあとの
# 差し替えで同じ画面を描くため、読み込みを1か所に置く。
# 別々に書くと、片方にだけ足した絞り込みや並びが差し替えで消える
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

    # 自分の希望リスト。順位順は関連が持っている。
    # 他人の希望は読まない。何人がその本を希望しているかは誰にも見せない
    # （docs/spec.md 8. 情報の可視性ルール）
    @wishes = @participation.wishes.includes(book: :registrant).load

    # 絞り込みは URL に残す。開き直しても同じ並びで戻れる。
    # 押せる口は2つしかないので、知らない値は全件に倒す
    @mine_only = params[:filter] == 'mine'
  end

  # 希望リストを変えたあとの差し替え。1冊出し入れする口と並べ替える口の両方から呼ぶ。
  # 1冊外すと後ろの順位がすべて繰り上がり、並べ替えれば全部の順位が変わるので、
  # 押した要素だけを差し替えると古い順位が残る。
  # 差し替えるのは一覧と希望リストの中身で、開閉の状態を持つシートの外枠は含めない
  def render_listing
    load_book_listing

    respond_to do |format|
      # 描く場所は口ごとに変えない。コントローラ名から引かせると、
      # 口が増えたときに同じ内容のテンプレートがもう1枚生える
      format.turbo_stream { render 'wishes/listing' }
      # JavaScript が無くても通る道を残す。絞り込みは URL に残っているので持ち回す
      format.html { redirect_to exchange_books_path(@exchange, filter: params[:filter].presence) }
    end
  end
end
