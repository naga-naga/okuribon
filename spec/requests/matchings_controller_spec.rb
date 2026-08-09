# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MatchingsController do
  # 下の exchange の日程に対して、各フェーズに落ちる時刻。
  # 締切は JST で決まるので、オフセットまで書いて日跨ぎの解釈を環境に委ねない
  let!(:phase_times) do
    { preparing: '2026-07-25T00:00:00+09:00', registration: '2026-08-04T00:00:00+09:00',
      wish: '2026-08-11T00:00:00+09:00', awaiting_matching: '2026-08-20T00:00:00+09:00',
      published: '2026-08-20T00:00:00+09:00' }.transform_values(&:in_time_zone).freeze
  end

  let!(:owner) { create(:user, display_name: 'みずき') }
  let!(:exchange) do
    create(:exchange,
           owner:,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end
  # 主催者の参加は factory が作る
  let!(:owner_participation) { exchange.participations.find_by!(user: owner) }

  # マッチング実行待ち。実行できる時刻の既定として使う
  let!(:awaiting_matching) { '2026-08-20T00:00:00+09:00'.in_time_zone }

  # 名前を問わない例では factory の既定に任せる
  def join(**attributes)
    create(:participation, exchange:, user: create(:user, **attributes))
  end

  def register(participation, count)
    create_list(:book, count, participation:)
  end

  # 全員が1冊ずつ登録し、互いの本を希望している。返却の出ない素直な成立
  def build_round_robin
    participations = [owner_participation, join(display_name: 'りく'), join(display_name: 'ゆうと')]
    books = participations.map { |participation| register(participation, 1).first }

    participations.each_with_index do |participation, index|
      others = books.reject { |book| book.participation_id == participation.id }
      others.rotate(index).each_with_index do |book, position|
        create(:wish, participation:, book:, position: position + 1)
      end
    end

    participations
  end

  describe '#new' do
    context '主催者のとき' do
      before { log_in_as(owner) }

      def open_confirmation(at: awaiting_matching)
        travel_to(at) { get new_exchange_management_matching_path(exchange) }
      end

      # 取り返しがつかない操作なので、ブラウザのダイアログではなく
      # 画面を1枚挟む（docs/spec.md 6.8）
      it '締切後は、やり直せないことを添えた確認画面が開く' do
        open_confirmation

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t('management.matching.confirm.heading'),
                                         I18n.t('management.matching.confirm.body'))
      end

      # 一覧を読み比べて自分で数えさせない。押す前に規模が分かるようにする
      it '割当の対象になる人数と冊数が出る' do
        register(owner_participation, 2)
        register(join, 1)
        join

        open_confirmation

        expect(response.body).to include(I18n.t('management.matching.confirm.target_value', people: 2, books: 3))
      end

      # 希望を出していない人にも余り物が回る。締め出されないことを押す前に伝える
      it '希望を出していない人数と、その人たちの扱いが出る' do
        register(owner_participation, 1)
        register(join, 1)

        open_confirmation

        expect(response.body).to include(I18n.t('management.matching.confirm.unsubmitted_value', count: 2))
      end

      # 自分が登録した本は受け取れないので（docs/spec.md 3.）、
      # 1人の登録冊数がほかの全員の合計を超えた分は登録者へ返る
      it '受け取り手のない本の冊数と行き先が出る' do
        register(owner_participation, 5)
        register(join, 1)
        register(join, 1)

        open_confirmation

        expect(response.body).to include(I18n.t('management.matching.confirm.returning_value', count: 3))
      end

      # 押す手前でもう一度読ませる。実行のボタンだけでは、
      # 画面を飛ばし読みした主催者がそのまま押してしまう
      it '理解したことを確かめるチェックが要る' do
        open_confirmation

        expect(response.body).to include(I18n.t('management.matching.confirm.acknowledge'), 'required')
      end

      it 'やめる先は管理画面' do
        open_confirmation

        expect(response.body).to include(I18n.t('management.matching.confirm.cancel'),
                                         exchange_management_path(exchange))
      end

      # 締切前に確認画面だけ開けても実行はできない。
      # 通らない道を先に見せると、押せると思わせたまま断ることになる
      it '希望提出期間のうちは開けない' do
        open_confirmation(at: phase_times.fetch(:wish))

        expect(response).to have_http_status(:conflict)
      end

      it '登録期間のうちは開けない' do
        open_confirmation(at: phase_times.fetch(:registration))

        expect(response).to have_http_status(:conflict)
      end

      # マッチングは一度だけ（CLAUDE.md「マッチング」）。
      # 実行済みの交換会で確認画面が開くと、二度目を押せるように見える
      it '実行済みなら開けない' do
        exchange.update!(matched_at: awaiting_matching)

        open_confirmation

        expect(response).to have_http_status(:conflict)
      end

      # ギフトコードが見えるのは登録した本人と受け取った人だけ（docs/spec.md 8.）。
      # 主催者に特権はなく、実行の直前でも変わらない
      it 'ギフトコードは含まれない' do
        create(:book, participation: join, gift_code: 'OTHERS-CODE-9999')
        create(:book, participation: owner_participation, gift_code: 'OWN-CODE-1111')

        open_confirmation

        expect(response.body).not_to include('OTHERS-CODE-9999')
        expect(response.body).not_to include('OWN-CODE-1111')
      end
    end

    # 403 だと、招待されていない交換会が実在することを URL を試すだけで
    # 確かめられてしまう（docs/spec.md 8.）
    it '参加しているだけの人には 404 を返す' do
      log_in_as(join.user)

      travel_to(awaiting_matching) { get new_exchange_management_matching_path(exchange) }

      expect(response).to have_http_status(:not_found)
    end

    it '参加していない人には 404 を返す' do
      log_in_as(create(:user))

      travel_to(awaiting_matching) { get new_exchange_management_matching_path(exchange) }

      expect(response).to have_http_status(:not_found)
    end

    it '未ログインならログイン画面へ送る' do
      travel_to(awaiting_matching) { get new_exchange_management_matching_path(exchange) }

      expect(response).to redirect_to(login_path)
    end
  end

  describe '#create' do
    def execute(target = exchange, at: awaiting_matching)
      travel_to(at) { post exchange_management_matching_path(target) }
    end

    context '主催者のとき' do
      before { log_in_as(owner) }

      it '割当が保存される' do
        participations = build_round_robin

        execute

        expect(Assignment.count).to eq(3)
        expect(participations.map { |participation| participation.assignments.count }).to all(eq(1))
      end

      # フェーズは状態カラムを持たず、実行日時の有無から導出する
      it '交換会が結果公開フェーズに入る' do
        build_round_robin

        execute

        expect(exchange.reload.matched_at).to eq(awaiting_matching)
        expect(exchange.phase(at: awaiting_matching)).to eq(:published)
      end

      # 押したのは主催者の操作なので、まず確かめたいのは実行が通ったこと。
      # 結果は交換会トップから、参加者として見に行く
      it '管理画面へ戻り、実行したことが伝わる' do
        build_round_robin

        execute

        expect(response).to redirect_to(exchange_management_path(exchange))
        follow_redirect!
        expect(response.body).to include(I18n.t('management.flash.matching_executed'))
      end

      # 締切前の実行はサーバー側で断る。ボタンを押せなくするだけでは、
      # フォームを直に送られたときに通ってしまう
      it '希望提出期間のうちは実行できず、割当も残らない' do
        build_round_robin

        execute(at: phase_times.fetch(:wish))

        expect(response).to have_http_status(:conflict)
        expect(Assignment.count).to eq(0)
        expect(exchange.reload.matched_at).to be_nil
      end

      it '登録期間のうちは実行できない' do
        build_round_robin

        execute(at: phase_times.fetch(:registration))

        expect(response).to have_http_status(:conflict)
        expect(Assignment.count).to eq(0)
      end

      # マッチングは一度だけ実行でき、再実行できない（CLAUDE.md「マッチング」）。
      # 二重送信で押されるのもこの経路なので、2回目は断られて割当も増えない
      it '二度送っても2回は実行されない' do
        build_round_robin

        execute
        assignments = Assignment.order(:id).pluck(:book_id, :participation_id)
        matched_at = exchange.reload.matched_at

        execute

        expect(response).to have_http_status(:conflict)
        expect(Assignment.order(:id).pluck(:book_id, :participation_id)).to eq(assignments)
        expect(exchange.reload.matched_at).to eq(matched_at)
      end

      # 実行を1回で終えるための備え。押した瞬間にボタンが使えなくなれば、
      # 手が滑って二度押すこと自体が起きない
      it '実行のボタンは送信中に押せなくなる' do
        travel_to(awaiting_matching) { get new_exchange_management_matching_path(exchange) }

        expect(response.body).to include('data-turbo-submits-with')
      end
    end

    # 403 だと、招待されていない交換会が実在することを URL を試すだけで
    # 確かめられてしまう（docs/spec.md 8.）
    it '参加しているだけの人には 404 を返し、実行もされない' do
      build_round_robin
      log_in_as(join.user)

      execute

      expect(response).to have_http_status(:not_found)
      expect(Assignment.count).to eq(0)
      expect(exchange.reload.matched_at).to be_nil
    end

    it '参加していない人には 404 を返し、実行もされない' do
      build_round_robin
      log_in_as(create(:user))

      execute

      expect(response).to have_http_status(:not_found)
      expect(Assignment.count).to eq(0)
    end

    it '未ログインならログイン画面へ送り、実行もされない' do
      build_round_robin

      execute

      expect(response).to redirect_to(login_path)
      expect(Assignment.count).to eq(0)
      expect(exchange.reload.matched_at).to be_nil
    end

    # ログインを挟むぶん、主催者以外の 404 とは応答が変わる。実在する交換会だけが
    # ログイン画面へ、存在しない id が 404 へ分かれると、未ログインのまま
    # id を試すだけで実在を確かめられてしまう（docs/spec.md 8.）
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      travel_to(awaiting_matching) do
        post exchange_management_matching_path(exchange)
        existing = [response.status, response.headers['Location']]

        post exchange_management_matching_path(Exchange.maximum(:id) + 1)

        expect([response.status, response.headers['Location']]).to eq(existing)
      end
    end
  end
end
