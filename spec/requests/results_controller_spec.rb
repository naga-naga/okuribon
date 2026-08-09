# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ResultsController do
  # 主催者はこの画面の見え方に関わらない。主催者に特権は無く（docs/spec.md 8.）、
  # 受け取った本があるかどうかだけで決まるので、factory の既定に任せる
  let!(:exchange) do
    create(:exchange,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end

  # 実行した時刻と、それを見に来る時刻。公開の日時が画面に出るので分けておく
  let!(:published_at) { '2026-08-20T21:04:00+09:00'.in_time_zone }
  let!(:opened_at) { '2026-08-21T09:00:00+09:00'.in_time_zone }

  let!(:viewer) { create(:user, display_name: 'あなた') }
  let!(:participation) { create(:participation, exchange:, user: viewer) }

  def join(display_name)
    create(:participation, exchange:, user: create(:user, display_name:))
  end

  # 割当はマッチングが作るが、ここで確かめたいのは見え方なので直に組む。
  # 実行そのものは Matching::Execution の spec が受け持つ
  def receive_book(from:, to: participation, **attributes)
    book = create(:book, participation: from, **attributes)
    create(:assignment, book:, participation: to, returned: false)
    book
  end

  # 返却は誰にも渡せなかった本が登録者へ戻ること。割当の受取人は登録者本人になる
  def return_book(of: participation, **attributes)
    book = create(:book, participation: of, **attributes)
    create(:assignment, book:, participation: of, round: nil, returned: true)
    book
  end

  def publish
    exchange.update!(matched_at: published_at)
  end

  def open_result(target = exchange, at: opened_at)
    travel_to(at) { get exchange_result_path(target) }
  end

  describe '#show' do
    context '結果が公開されているとき' do
      before { log_in_as(viewer) }

      # 取得枠は登録した冊数と同数（docs/spec.md 3.）。
      # 受け取った本がその冊数だけ並ぶ
      it '受け取った本が取得枠の冊数だけ並ぶ' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所')
        receive_book(from: join('はるか'), title: '十三番目の便り')
        publish

        open_result

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('波打ち際の観測所', '十三番目の便り')
      end

      # 誰から贈られたかが分かるようにする。お礼を伝えるため（docs/spec.md 6.5）
      it '誰が登録した本かが分かる' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所',
                     recommendation: '後半で数字の意味が反転します')
        publish

        open_result

        expect(response.body).to include(I18n.t('result.from', name: 'ゆうと'),
                                         '後半で数字の意味が反転します')
      end

      # 一度見えたら取り消せない。伏せ字が既定で、明示的な操作で開く（docs/spec.md 10.）
      it 'ギフトコードは伏せ字で入り、表示とコピーの口が付く' do
        receive_book(from: join('ゆうと'), gift_code: 'MINE-CODE-0001')
        publish

        open_result

        expect(response.body).to include('MINE-CODE-0001', 'type="password"',
                                         I18n.t('result.gift_code.reveal'),
                                         I18n.t('result.gift_code.copy'))
      end

      # ギフトコードが見えるのは登録した本人と、受け取った人だけ（docs/spec.md 8.）
      it '他人が受け取った本のギフトコードは含まれない' do
        others = join('ゆうと')
        receive_book(from: join('はるか'), to: others, gift_code: 'OTHERS-CODE-9999')
        publish

        open_result

        expect(response.body).not_to include('OTHERS-CODE-9999')
      end

      # 渡った先の人が使うコードなので、この画面には取り出す用がない。
      # 本人には見える値だが（docs/spec.md 8.）、並べる理由が無い
      it '自分が渡した本のギフトコードは含まれない' do
        mine = create(:book, participation:, gift_code: 'GIVEN-CODE-2222')
        create(:assignment, book: mine, participation: join('ゆうと'), returned: false)
        publish

        open_result

        expect(response.body).not_to include('GIVEN-CODE-2222')
      end

      # 数週間ずっと締切を見せてきた画面なので、いつ公開されたのかを添える
      it '公開された日時が出る' do
        receive_book(from: join('ゆうと'))
        publish

        open_result

        expect(response.body).to include(I18n.l(published_at, format: :schedule))
      end
    end

    context '自分の本が返却されたとき' do
      before { log_in_as(viewer) }

      # 誰にも渡らなかったのは相性の問題で、本の評価ではない。
      # 事実だけを出すと、選ばれなかったことを評価として読んでしまう
      it 'やわらかい文言で返却が伝わる' do
        receive_book(from: join('ゆうと'))
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include(I18n.t('result.returned.heading_one', title: '砂の図書館'),
                                         I18n.t('result.returned.body'))
      end

      # 本の詳細画面を持たないため（docs/spec.md 6.3）、誰にも渡らなかった
      # コードの取り出し口はこの画面以外に無い
      it '返却された本のギフトコードを、受け取った本と同じ形で開ける' do
        return_book(title: '砂の図書館', gift_code: 'RETURNED-CODE-3333')
        publish

        open_result

        expect(response.body).to include('RETURNED-CODE-3333',
                                         I18n.t('result.gift_code.note_returned'))
      end

      it '2冊以上戻ってきたときは、冊数と題名が並ぶ' do
        return_book(title: '砂の図書館')
        return_book(title: '金曜日の献立')
        publish

        open_result

        expect(response.body).to include(I18n.t('result.returned.heading_many', count: 2),
                                         '砂の図書館', '金曜日の献立')
      end
    end

    # 取得枠は登録した冊数と同数（docs/spec.md 3.）。
    # 白紙で返すと、壊れているのか受け取れなかったのか区別がつかない
    context '受け取った本が1冊も無いとき' do
      before { log_in_as(viewer) }

      it '1冊も登録していない人には、枠が0だったことを伝える' do
        publish

        open_result

        expect(response.body).to include(I18n.t('result.empty.no_slots.heading'),
                                         I18n.t('result.empty.no_slots.body'))
      end

      # 登録はしたのに回ってこないことがある。枠が0だったのと同じ文にすると、
      # 登録し忘れたのかと本人が疑う
      it '登録はしたが回ってこなかった人には、別の事情を伝える' do
        return_book(title: '砂の図書館')
        publish

        open_result

        expect(response.body).to include(I18n.t('result.empty.none.heading'),
                                         I18n.t('result.empty.none.body'))
      end
    end

    # 結果公開前に開ける画面ではない。導線もこのフェーズには出ないので、
    # ここへ来るのは URL を直に打った場合だけ
    context '結果が公開されていないとき' do
      before { log_in_as(viewer) }

      it 'まだ公開されていないことを添えて 404 を返す' do
        open_result(at: '2026-08-16T00:00:00+09:00'.in_time_zone)

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include(I18n.t('result.unpublished.heading'))
      end

      it '受け取る本の中身は出さない' do
        receive_book(from: join('ゆうと'), title: '波打ち際の観測所', gift_code: 'MINE-CODE-0001')

        open_result(at: '2026-08-16T00:00:00+09:00'.in_time_zone)

        expect(response.body).not_to include('波打ち際の観測所')
        expect(response.body).not_to include('MINE-CODE-0001')
      end
    end

    it '参加していない人には 404 を返す' do
      publish
      log_in_as(create(:user))

      open_result

      expect(response).to have_http_status(:not_found)
    end

    it '未ログインならログイン画面へ送る' do
      publish

      open_result

      expect(response).to redirect_to(login_path)
    end

    # 実在する交換会だけがログイン画面へ、存在しない id が 404 へ分かれると、
    # ログインしないまま id を試すだけで実在を確かめられてしまう（docs/spec.md 8.）
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      publish

      open_result
      existing = [response.status, response.headers['Location']]

      open_result(Exchange.maximum(:id) + 1)

      expect([response.status, response.headers['Location']]).to eq(existing)
    end
  end
end
