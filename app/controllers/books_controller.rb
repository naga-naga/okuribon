# frozen_string_literal: true

class BooksController < ApplicationController
  before_action :require_login

  # 本の一覧。交換会トップと同じく参加から引くので、参加していなければ見つからない。
  # 読み取りは全フェーズで開いており、止めるのは書き込みだけ（docs/spec.md 4. フェーズ）。
  # 登録順に並べる。開くたびにカードの位置が入れ替わると、
  # 前に見た本を毎回探し直すことになる
  def index
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:exchange_id))
    @exchange = @participation.exchange
    # 冊数の表示と空の判定にも同じ本を使うので、その場で読み込む。
    # 関連のままだと、並べる前に COUNT と EXISTS が別々に飛ぶ
    @books = @exchange.books.includes(:registrant).order(:created_at, :id).load
  end
end
