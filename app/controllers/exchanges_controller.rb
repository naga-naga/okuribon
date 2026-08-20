# frozen_string_literal: true

class ExchangesController < ApplicationController
  include BookListing
  include ParticipatingExchange

  before_action :require_login

  # 並ぶのは参加している交換会だけ。主催者は必ず参加者を兼ねるので、
  # 主催した交換会もここに並ぶ。カード1枚に載るものは交換会だけでは足りず、
  # 並び順も日時から導出するので、組み立てはサービスに置く
  def index
    @cards = Exchanges::Listing.new(current_user, at: requested_at).call
  end

  # 交換会ページ。状態ヘッダー（docs/spec.md 6.1）と本の一覧（6.2）を1枚で出す。
  # 参加から引くので、参加していなければ見つからない。主催者も参加者を兼ねるので
  # ここを開ける。主催者管理画面への導線もこの画面が持つ。
  # 自分の取得枠を出すのに参加そのものが要るため、交換会ではなく参加を引いて、
  # 権限の判定と取り出しを1回で済ませる。
  # 読み取りは5フェーズすべてで開いており、止めるのは書き込みだけ（4. フェーズ）
  def show
    # ネストされた口と違い、ここだけ交換会 id が :id で来る
    set_participation(params.expect(:id))
    # 状態ヘッダーの「あなたがすること」。フェーズだけでは決まらず自分の状態で
    # 変わるので、組み立てはサービスに置く（交換会一覧も同じ文言を並べる）
    @todo = Exchanges::Todo.new(@participation, at: requested_at).call
    # 下半分に並ぶ本と希望リスト。希望を出し入れしたあとの差し替えと
    # 同じ読み込みを通す。別々に書くと、片方にだけ足した並びが差し替えで消える
    load_book_listing
  end

  def new
    @exchange = Exchange.new
  end

  def edit
    @exchange = owned_exchange
  end

  # 交換会と主催者の参加を1つのトランザクションで作る。
  # 締切の判定に基準時刻が要ることもあり、組み立てはサービスに置く
  def create
    @exchange = Exchanges::Creation.new(owner: current_user,
                                        attributes: exchange_params,
                                        at: requested_at).call

    if @exchange.persisted?
      # 作った本人はもう参加者なので、そのままトップへ入れる
      redirect_to exchange_path(@exchange), notice: t('exchange.flash.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    @exchange = owned_exchange

    if @exchange.update(exchange_params)
      redirect_to edit_exchange_path(@exchange), notice: t('exchange.flash.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  # 主催者の交換会だけを引く。見つからなければ 404 になり、主催者以外には
  # 存在そのものを伏せる。403 を返すと、招待されていない交換会の実在が漏れる
  def owned_exchange
    current_user.owned_exchanges.find(params.expect(:id))
  end

  # 主催者はログイン中の利用者から決める。送られてきた owner_id は受け取らない。
  # 招待トークンと乱数シードもモデルが発行するので、フォームからは触らせない。
  # 希望提出期間の開始は registration_ends_at から導出する属性で、カラムが無い
  def exchange_params
    params.expect(exchange: [:name, :description, :webhook_url,
                             :registration_starts_at, :registration_ends_at, :wish_ends_at])
  end
end
