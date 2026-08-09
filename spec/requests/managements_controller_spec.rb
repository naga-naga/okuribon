# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ManagementsController do
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
           name: '冬の読書交換会',
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end
  # 主催者の参加は factory が作る
  let!(:owner_participation) { exchange.participations.find_by!(user: owner) }

  let!(:registration_phase) { '2026-08-04T00:00:00+09:00' }

  def join(display_name)
    create(:participation, exchange:, user: create(:user, display_name:))
  end

  describe '#show' do
    context '主催者のとき' do
      before { log_in_as(owner) }

      it '参加者の名前と登録冊数が並ぶ' do
        create_list(:book, 2, participation: owner_participation)
        create(:book, participation: join('ゆうと'))

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('みずき', '2冊', 'ゆうと', '1冊')
      end

      # 見出しの数は交換会全体の規模。一覧を数え直さずに掴めるようにする
      it '参加人数と登録された総冊数が見出しに出る' do
        create_list(:book, 2, participation: owner_participation)
        create(:book, participation: join('ゆうと'))

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include('2人・3冊')
      end

      it '希望を出した人には冊数が、出していない人には未提出と出る' do
        wisher = join('はるか')
        join('かなえ')
        books = create_list(:book, 3, participation: owner_participation)
        books.each_with_index { |book, index| create(:wish, participation: wisher, book:, position: index + 1) }

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include('提出済み 3冊', '未提出')
      end

      # 参加日は「いつから居るか」を測る手掛かりになる。
      # 締切間際に入った人が希望を出していないのは、忘れているとは限らない
      it '参加日が出る' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.l(owner_participation.created_at.to_date, format: :compact))
      end

      # 主催者に特権はない（docs/spec.md 8.）。自分の本のコードも、
      # 取得経路をこの画面に増やさないためここには出さない
      it '他人のギフトコードもこの画面には出ない' do
        create(:book, participation: join('ゆうと'), gift_code: 'OTHERS-CODE-9999')
        create(:book, participation: owner_participation, gift_code: 'OWN-CODE-1111')

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).not_to include('OTHERS-CODE-9999')
        expect(response.body).not_to include('OWN-CODE-1111')
      end

      # 誰が何を希望したかは主催者にも見せない。
      # 見えると、割当の前から結果を組み替えられる立場になってしまう
      it '誰がどの本を希望したかは出ない' do
        wisher = join('はるか')
        book = create(:book, participation: owner_participation, title: '掃除婦のための手引き書')
        create(:wish, participation: wisher, book:, position: 1)

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).not_to include('掃除婦のための手引き書')
      end

      # 作った直後の交換会がこの状態にあたる。参加者は主催者ひとりで、
      # 本も希望もまだ無い
      it '参加者が主催者ひとりでも開ける' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('みずき', '0冊')
      end

      # 招待URLは人に渡すものなので、貼り付けてそのまま開ける形で出す。
      # パスだけを出すと、渡された側が自分でホストを補うことになる
      it '招待URLがホストごと出る' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(invitation_url(exchange.invite_token))
      end

      # 日程は主催者が動かせる。いま何がいつまでなのかを、編集画面を開かずに掴めるようにする
      it '各期間の開始と終了が並ぶ' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include('登録期間', '希望提出期間',
                                         I18n.l(exchange.registration_starts_at, format: :schedule),
                                         I18n.l(exchange.registration_ends_at, format: :schedule),
                                         I18n.l(exchange.wish_ends_at, format: :schedule))
      end

      # どの期間がいま動いているかを添える。日時を読み比べさせない
      it '期間の状態が出る' do
        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('exchange.schedule.states.done'),
                                         I18n.t('exchange.schedule.states.current'))
      end

      # 日時の入力欄は交換会の編集画面に1つだけ置く（docs/spec.md 6.9）。
      # ここは現在の日程を見せて、変更はそちらへ送る
      it '変更は交換会の編集画面へ送る' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(edit_exchange_path(exchange))
      end

      # 締切を動かすと、参加者の画面の残り時間もその場で変わる。
      # フェーズは状態カラムを持たず日時から導出するため
      it '締切の変更が参加者に即座に効くことを添える' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.schedule.note'))
      end

      # 結果公開後も日程は変更できる（docs/spec.md 6.9）。ただし動かしても
      # 結果公開のままなので、締切を戻せば登録が開き直ると読ませない
      it '結果公開後は、日程を変えても再開しないことを添える' do
        at = phase_times.fetch(:published)
        exchange.update!(matched_at: at)

        travel_to(at) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.schedule.note_published'))
        expect(response.body).not_to include(I18n.t('management.schedule.note'))
      end

      # 押すと古いURLが開けなくなる。取り消せないので、押す前に断りを出す
      it '再発行には確認が挟まる' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include('data-turbo-confirm', I18n.t('management.invite_url.reissue_confirm'))
      end

      # 日時が動いても開ける画面にする。締切を延ばすのも実行するのも
      # この画面の仕事なので、フェーズで閉じると主催者が入れなくなる
      it 'どのフェーズでも開ける' do
        Exchange::PHASES.each do |phase|
          at = phase_times.fetch(phase)
          # 結果公開はフェーズ導出の入口が違う。日時ではなく実行済みかどうかで決まる
          exchange.update!(matched_at: phase == :published ? at : nil)

          travel_to(at) { get exchange_management_path(exchange) }

          expect(exchange.phase(at:)).to eq(phase)
          expect(response).to have_http_status(:ok), "#{phase} で開けなかった"
        end
      end
    end

    # 403 だと、招待されていない交換会が実在することを URL を試すだけで
    # 確かめられてしまう（docs/spec.md 8.）
    it '参加しているだけの人には 404 を返す' do
      participant = create(:user)
      create(:participation, exchange:, user: participant)
      log_in_as(participant)

      travel_to(registration_phase) { get exchange_management_path(exchange) }

      expect(response).to have_http_status(:not_found)
    end

    it '参加していない人には 404 を返す' do
      log_in_as(create(:user))

      travel_to(registration_phase) { get exchange_management_path(exchange) }

      expect(response).to have_http_status(:not_found)
    end

    it '未ログインならログイン画面へ送る' do
      travel_to(registration_phase) { get exchange_management_path(exchange) }

      expect(response).to redirect_to(login_path)
    end

    # ログインを挟むぶん、主催者以外の 404 とは応答が変わる。実在する交換会だけが
    # ログイン画面へ、存在しない id が 404 へ分かれると、未ログインのまま
    # id を試すだけで実在を確かめられてしまう（docs/spec.md 8.）。
    # require_login が Exchange を引く前に返すことで、両者は同じ応答になる。
    # 交換会を先に引く形へ直すと、ここが落ちる
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      travel_to(registration_phase) do
        get exchange_management_path(exchange)
        existing = [response.status, response.headers['Location']]

        get exchange_management_path(Exchange.maximum(:id) + 1)

        expect([response.status, response.headers['Location']]).to eq(existing)
      end
    end
  end
end
