# frozen_string_literal: true

class BooksController < ApplicationController
  include PhaseGuard

  before_action :require_login
  before_action :set_participation

  # フォームを開く時点で止める。押しても通らない画面を開かせても仕方がない。
  # only: ではなく except: にして、既定を「止める」に倒す。
  # 書き込みのアクションが増えたときに、書き忘れが素通りにならない。
  # index は交換会ページへ送るだけで、行き先は全フェーズで開いている
  guard_phase :book, except: [:index]

  # 本の一覧は交換会ページに畳んだ（docs/spec.md 6.1 / 6.2）。同じものを指す URL を
  # 2つ残すと、交換会一覧のカードやパンくずがどちらを指すのかを画面ごとに選ぶことに
  # なるので、経路は残したまま交換会ページへ送る。すでに配られたリンクのため。
  # 絞り込みは交換会ページの URL のクエリに載るので、そのまま持ち回す
  def index
    redirect_to exchange_path(@exchange, filter: params[:filter].presence),
                status: :moved_permanently
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
      redirect_to after_create_path,
                  notice: t('book.flash.created', title: @book.title, count: @participation.books.count)
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @book = own_book

    if @book.update(book_params)
      redirect_to exchange_path(@exchange), notice: t('book.flash.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    own_book.destroy!

    redirect_to exchange_path(@exchange), notice: t('book.flash.destroyed')
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

  # 「登録して、続けてもう1冊」で来たときだけフォームへ戻す。
  # 何冊でも登録できるので、毎回一覧を経由させると1冊ごとに2画面を往復することになる
  def after_create_path
    return new_exchange_book_path(@exchange) if params[:continue].present?

    exchange_path(@exchange)
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
