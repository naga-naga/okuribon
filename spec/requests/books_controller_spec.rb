# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BooksController do
  let!(:user) { create(:user) }
  let!(:exchange) { create(:exchange, name: '夏の交換会') }
  let!(:participation) { create(:participation, user:, exchange:) }

  before { log_in_as(user) }

  describe '#index' do
    def open_list
      get exchange_books_path(exchange)
    end

    # 登録者を名前で撒くための入れ物。参加を伴わない本は作れない
    def book_by(display_name, **attributes)
      registrant = create(:participation, exchange:, user: create(:user, display_name:))
      create(:book, participation: registrant, **attributes)
    end

    it '参加者は開ける' do
      open_list

      expect(response).to have_http_status(:ok)
    end

    # 選ぶ材料は全員の本。自分の登録した本だけでは読み比べにならない
    it '全員の本が並ぶ' do
      create(:book, participation:, title: '自分の本')
      book_by('佐藤 花子', title: '他の人の本')

      open_list

      expect(response.body).to include('自分の本')
      expect(response.body).to include('他の人の本')
    end

    it '誰が登録したかが分かる' do
      book_by('佐藤 花子')

      open_list

      expect(response.body).to include('佐藤 花子')
    end

    # 数行のテキストを丸ごと並べると、一覧をざっと眺められなくなる
    it '長いあらすじは冒頭だけ出る' do
      book_by('佐藤 花子', summary: "#{'あ' * 200}ここは切られる")

      open_list

      expect(response.body).to include('あ' * 50)
      expect(response.body).not_to include('ここは切られる')
    end

    it '短いあらすじはそのまま出る' do
      book_by('佐藤 花子', summary: 'ある町に住む青年が、古い書店で一冊の本と出会う。')

      open_list

      expect(response.body).to include('ある町に住む青年が、古い書店で一冊の本と出会う。')
    end

    # 読み比べがこの画面の目的。本の詳細（#23）がまだ無いので、
    # ここで切ると続きを読む先がどこにも無い
    it 'おすすめポイントは全文出る' do
      book_by('佐藤 花子', recommendation: "#{'ぜ' * 200}最後まで読める")

      open_list

      expect(response.body).to include('最後まで読める')
    end

    # 見えるのは登録した本人と、成立後の受取人だけ。一覧はどちらの経路でもない
    it 'ギフトコードが含まれない' do
      create(:book, participation:, gift_code: 'MYOWNGIFTCODE')
      book_by('佐藤 花子', gift_code: 'OTHERGIFTCODE')

      open_list

      expect(response.body).not_to include('MYOWNGIFTCODE')
      expect(response.body).not_to include('OTHERGIFTCODE')
    end

    # 開くたびにカードの位置が入れ替わると、前に見た本を探し直すことになる
    it '登録順に並ぶ' do
      create(:book, participation:, title: '先に登録した本')
      create(:book, participation:, title: 'あとで登録した本')

      open_list

      expect(response.body.index('先に登録した本')).to be < response.body.index('あとで登録した本')
    end

    # 白紙で返すと、壊れているのかまだ誰も登録していないのか区別がつかない
    it '1冊も登録されていなければその旨を出す' do
      open_list

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('まだ本は登録されていません')
    end

    # 403 だと、招待されていない交換会の実在が URL を試すだけで確かめられる
    it '参加していなければ見つからない' do
      log_in_as(create(:user))

      open_list

      expect(response).to have_http_status(:not_found)
    end

    # 主催者は必ず参加者を兼ねるので、自分の交換会の一覧を開ける
    it '主催者も開ける' do
      owned = create(:exchange, owner: user)

      get exchange_books_path(owned)

      expect(response).to have_http_status(:ok)
    end

    it 'ログインしていなければログイン画面へ送る' do
      log_out

      open_list

      expect(response).to redirect_to(login_path)
    end

    # 読み取りは全フェーズで開いている。止めるのは書き込みだけ
    # （docs/spec.md 4. フェーズ）
    [
      ['準備中', '2026-07-25T00:00:00+09:00'],
      ['登録期間', '2026-08-04T00:00:00+09:00'],
      ['希望提出期間', '2026-08-11T00:00:00+09:00'],
      ['マッチング実行待ち', '2026-08-20T00:00:00+09:00'],
    ].each do |phase, now|
      it "#{phase}でも開ける" do
        exchange.update!(registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
                         registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
                         wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)

        travel_to(now) { open_list }

        expect(response).to have_http_status(:ok)
      end
    end

    it '結果公開でも開ける' do
      exchange.update!(matched_at: 1.day.ago)

      open_list

      expect(response).to have_http_status(:ok)
    end
  end
end
