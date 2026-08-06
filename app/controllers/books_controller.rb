# frozen_string_literal: true

class BooksController < ApplicationController
  include PhaseGuard

  before_action :require_login
  before_action :set_participation

  # フォームを開く時点で止める。押しても通らない画面を開かせても仕方がない。
  # only: ではなく except: にして、既定を「止める」に倒す。
  # 書き込みのアクションが増えたときに、書き忘れが素通りにならない。
  # 読み取りは全フェーズで開くので、詳細（#23）を足すときはここに並べる
  guard_phase :book, except: [:index]

  # 本の一覧。交換会トップと同じく参加から引くので、参加していなければ見つからない。
  # 読み取りは全フェーズで開いており、止めるのは書き込みだけ（docs/spec.md 4. フェーズ）。
  # 登録順に並べる。開くたびにカードの位置が入れ替わると、
  # 前に見た本を毎回探し直すことになる
  def index
    # 冊数の表示と空の判定にも同じ本を使うので、その場で読み込む。
    # 関連のままだと、並べる前に COUNT と EXISTS が別々に飛ぶ
    @books = @exchange.books.includes(:registrant).order(:created_at, :id).load
  end

  def new
    @book = @participation.books.build
  end

  def edit
    @book = own_book
  end

  def create
    @book = @participation.books.build(book_params)

    if @book.save
      redirect_to exchange_books_path(@exchange), notice: t('book.flash.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @book = own_book

    if @book.update(book_params)
      redirect_to exchange_books_path(@exchange), notice: t('book.flash.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    own_book.destroy!

    redirect_to exchange_books_path(@exchange), notice: t('book.flash.destroyed')
  end

  private

  # 交換会は参加から引く。参加していなければ見つからない。
  # 読み取りと書き込みで入口を分けると、片方だけ緩む
  def set_participation
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:exchange_id))
    @exchange = @participation.exchange
  end

  # フェーズの判定対象。PhaseGuard から呼ばれる
  def current_exchange
    @exchange
  end

  # 自分の本だけを引く。他人の本は見つからないことにする。
  # 403 を返すと、その id の本が実在することを URL を試すだけで確かめられる
  def own_book
    @participation.books.find(params.expect(:id))
  end

  # 登録者は参加から決める。送られてきた participation_id は受け取らない
  def book_params
    params.expect(book: [:title, :summary, :url, :recommendation, :gift_code])
  end
end
