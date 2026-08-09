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

  def register(display_name, count)
    create_list(:book, count, participation: join(display_name))
  end

  # りくの5冊に対してほかの全員は合わせて2冊。自分が登録した本は受け取れないので、
  # 差の3冊は渡す相手がいない（docs/spec.md 6.8）
  def register_imbalanced
    register('りく', 5)
    register('ゆうと', 1)
    register('はるか', 1)
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

      # 自分が登録した本は受け取れないので（docs/spec.md 3.）、1人の登録冊数が
      # ほかの全員の合計を超えた分は、渡す相手がいないまま残る
      it '受け取り手のない冊数を添えて警告する' do
        register_imbalanced

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.imbalance.heading', returning: 3))
      end

      # 誰に追加登録を促せばよいかを、一覧の冊数を見比べずに掴めるようにする
      it '偏りの元になっている人と、ほかの全員の合計を出す' do
        register_imbalanced

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(
          I18n.t('management.imbalance.body', name: 'りく', books: 5, others: 2, returning: 3)
        )
      end

      # 余った本は登録者へ返る。コードが未使用のまま残ることまで書かないと、
      # 返却された本のギフトコードがどうなるのかを主催者が探すことになる
      it '余った本の行き先を添える' do
        register_imbalanced

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.imbalance.returned', name: 'りく'))
      end

      # 打つ手は登録期間を延ばして追加登録を促すことだけ。
      # 日時の入力欄は交換会の編集画面に1つだけ置く（docs/spec.md 6.9）
      it '登録期間を延ばす導線を添える' do
        register_imbalanced

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.imbalance.remedy'),
                                         edit_exchange_path(exchange))
      end

      # 締切を過ぎてからでは主催者にできることがない（docs/spec.md 6.8）
      it '登録の締切を過ぎたら警告が消える' do
        register_imbalanced

        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(I18n.t('management.imbalance.eyebrow'))
      end

      # 結果公開後は日程を戻しても登録が再開しない（docs/spec.md 6.9）。
      # 締切を動かして警告だけが戻ってきても、打つ手はもう無い
      it '結果公開後は、日程を登録期間へ戻しても警告が出ない' do
        register_imbalanced
        exchange.update!(matched_at: phase_times.fetch(:published))

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(I18n.t('management.imbalance.eyebrow'))
      end

      it '冊数が釣り合っていれば警告が出ない' do
        register('りく', 1)
        register('ゆうと', 1)

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(I18n.t('management.imbalance.eyebrow'))
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

      # 除外できるのは参加できる期間と同じく登録の締切まで（docs/spec.md 4.）
      it '登録期間中なら、参加者の行に除外の口が出る' do
        participation = join('ゆうと')

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(exchange_management_participant_path(exchange, participation))
      end

      # 外すと本もギフトコードも消える。取り消せないので、押す前に断りを出す
      it '除外には確認が挟まる' do
        join('ゆうと')

        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include('data-turbo-confirm',
                                         I18n.t('management.participants.exclude_confirm', name: 'ゆうと'))
      end

      # 主催者は必ず参加者を兼ねる（docs/spec.md 6.9）。押しても 403 になる口は出さない
      it '主催者自身の行には除外の口が出ない' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(exchange_management_participant_path(exchange, owner_participation))
      end

      it '登録の締切を過ぎていれば、除外の口が出ない' do
        participation = join('ゆうと')

        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(exchange_management_participant_path(exchange, participation))
      end

      # 出ない理由を書かないと、主催者が探しに行くことになる
      it '除外できる期限を添える' do
        travel_to(registration_phase) { get exchange_management_path(exchange) }

        expect(response.body).to include(
          I18n.t('management.participants.exclusion_open',
                 at: I18n.l(exchange.registration_ends_at, format: :schedule))
        )
      end

      it '締切後は、もう外せないことを添える' do
        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).to include(
          I18n.t('management.participants.exclusion_closed',
                 at: I18n.l(exchange.registration_ends_at, format: :schedule))
        )
      end

      # 締切前でも、実行が主催者の仕事であることは伝えておく。
      # 締切を過ぎて初めて知らせるのでは、待っているあいだ誰も動かない
      it '締切前は、締切後に実行することと押せる日時が出る' do
        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).to include(
          I18n.t('management.matching.waiting.heading'),
          I18n.t('management.matching.waiting.body',
                 at: I18n.l(exchange.wish_ends_at, format: :schedule))
        )
      end

      # 締切前に確認画面へ送っても、そちらが 409 を返す。
      # 押しても断られる口は残さない（docs/spec.md 6.8）
      it '締切前は確認画面への口が出ない' do
        travel_to(phase_times.fetch(:wish)) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(new_exchange_management_matching_path(exchange))
      end

      # 押し忘れが起きやすいので大きく促す。実行するまで誰も結果を見られない
      it '締切後は、実行を促す見出しが出る' do
        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.awaiting.heading'))
      end

      # 何日放っておいたのかを、締切の日時から数えさせない
      it '締切後は、締切からの経過が出る' do
        at = exchange.wish_ends_at + 14.hours

        travel_to(at) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.awaiting.elapsed', elapsed: '14時間'))
      end

      it '締切後は、確認画面への口が出る' do
        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(new_exchange_management_matching_path(exchange))
      end

      # 押した先で確認が挟まることを添える。取り返しのつかない操作なので、
      # 押した瞬間に確定すると思わせない
      it '締切後は、押しても確定しないことを添える' do
        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.awaiting.note'))
      end

      # 希望を出していない人にも余り物が回る。実行前に、
      # その人たちが締め出されるわけではないと分かるようにする
      it '締切後、希望未提出の人がいれば人数とその扱いが出る' do
        create_list(:book, 1, participation: owner_participation)
        create(:book, participation: join('ゆうと'))

        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.checklist.unsubmitted', count: 2))
      end

      # 0冊は締め出しではなく仕組みの結果（docs/spec.md 6.9）
      it '締切後、1冊も登録していない人がいれば人数が出る' do
        create(:book, participation: owner_participation)
        join('たける')

        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.checklist.without_books', count: 1))
      end

      # 実行するほかに、締切を延ばして待つ道もある。
      # 日時の入力欄は交換会の編集画面に1つだけ置く（docs/spec.md 6.9）
      it '締切後、気になる点があれば締切を延ばす道を添える' do
        create(:book, participation: owner_participation)
        join('たける')

        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).to include(I18n.t('management.matching.checklist.extend'),
                                         edit_exchange_path(exchange))
      end

      # 未提出も0冊もいないなら、実行の前に確かめることは無い
      it '締切後、気になる点が無ければ確認の一覧が出ない' do
        books = create_list(:book, 1, participation: owner_participation)
        wisher = join('ゆうと')
        create(:book, participation: wisher)
        create(:wish, participation: wisher, book: books.first, position: 1)
        create(:wish, participation: owner_participation, book: wisher.books.first, position: 1)

        travel_to(phase_times.fetch(:awaiting_matching)) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(I18n.t('management.matching.checklist.heading'))
      end

      # マッチングは一度だけ（CLAUDE.md「マッチング」）。
      # ボタンが残っていると、二度目を押せるように見える
      it '実行済みならボタンが消え、実行日時が出る' do
        at = phase_times.fetch(:published)
        exchange.update!(matched_at: at)

        travel_to(at) { get exchange_management_path(exchange) }

        expect(response.body).not_to include(new_exchange_management_matching_path(exchange))
        expect(response.body).to include(I18n.t('management.matching.done.heading'),
                                         I18n.t('management.matching.done.body',
                                                at: I18n.l(at, format: :schedule)))
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
