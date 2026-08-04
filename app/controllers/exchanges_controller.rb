# frozen_string_literal: true

class ExchangesController < ApplicationController
  before_action :require_login

  # 並ぶのは参加している交換会だけ。主催しているだけのものは含まれない。
  # 並び順を決めないと開くたびにカードの位置が入れ替わる。参加数は多くても
  # 十数件なので、フェーズをまたいで凝った順序は作らず、日程の新しい順にする
  def index
    @exchanges = current_user.exchanges.order(registration_starts_at: :desc)
  end

  # 交換会トップ。参加から引くので、参加していなければ見つからない。
  # 主催しているだけの人もここには入れない。主催者としての導線は
  # 主催者管理画面（#36）が持つ。自分の取得枠を出すのに参加そのものが要るため、
  # 交換会ではなく参加を引いて、権限の判定と取り出しを1回で済ませる
  def show
    @participation = current_user.participations.find_by!(exchange_id: params.expect(:id))
    @exchange = @participation.exchange
  end

  def new
    @exchange = Exchange.new
  end

  def edit
    @exchange = owned_exchange
  end

  def create
    @exchange = current_user.owned_exchanges.build(exchange_params)

    if @exchange.save
      # 交換会トップへは送らない。作った時点では主催者はまだ参加者ではなく、
      # トップは参加者しか開けないため 404 になる
      redirect_to edit_exchange_path(@exchange), notice: t('exchange.flash.created')
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
