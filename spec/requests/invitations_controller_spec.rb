# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvitationsController do
  let!(:owner) { create(:user, display_name: '主催 太郎') }
  let!(:exchange) do
    create(:exchange, owner:,
                      name: '夏の交換会',
                      description: 'Kindle のみ。1000円前後を目安に。',
                      registration_starts_at: '2026-08-10T10:00:00+09:00'.in_time_zone,
                      registration_ends_at: '2026-08-24T10:00:00+09:00'.in_time_zone,
                      wish_ends_at: '2026-09-07T10:00:00+09:00'.in_time_zone)
  end

  describe '#show' do
    # 存在しない交換会と、招待されていない交換会を見分けられないようにする
    it '無効なトークンでは見つからない' do
      get invitation_path('deadbeefdeadbeef')

      expect(response).to have_http_status(:not_found)
    end

    # 招待された人はまだログインしていない。何の集まりかを見てから決められるようにする
    describe '交換会の概要' do
      before { get invitation_path(exchange.invite_token) }

      it '未ログインでも開ける' do
        expect(response).to have_http_status(:ok)
      end

      it '交換会名と概要が出る' do
        expect(response.body).to include('夏の交換会')
        expect(response.body).to include('Kindle のみ。1000円前後を目安に。')
      end

      it '主催者名が出る' do
        expect(response.body).to include('主催 太郎')
      end

      it '参加者数が出る' do
        create_list(:participation, 2, exchange:)

        get invitation_path(exchange.invite_token)

        expect(response.body).to include('2人')
      end

      # UTC で描かれると9時間ずれた日程が出て、参加を決める判断そのものが狂う
      it '各期間の日程が JST で出る' do
        expect(response.body).to include('2026年8月10日 10:00')
        expect(response.body).to include('2026年8月24日 10:00')
        expect(response.body).to include('2026年9月7日 10:00')
      end
    end

    describe '未ログインのとき' do
      before { get invitation_path(exchange.invite_token) }

      it '「参加する」でログインへ送る' do
        expect(response.body).to include('参加する')
        expect(response.body).to include('action="/auth/google_oauth2"')
      end

      # 戻り先はサーバーが見たパスだけを覚える。パラメータや Referer から
      # 受け取ると、もっともらしい招待リンクで認証直後に外部サイトへ落とせる
      it 'ログインしたら招待URLへ戻す' do
        log_in_as(create(:user))

        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end
    end

    # 交換会トップ（#19）が入ったら、この画面には留めずトップへ送る
    describe '参加済みのとき' do
      let!(:participant) { create(:user) }

      before do
        create(:participation, exchange:, user: participant)
        log_in_as(participant)

        get invitation_path(exchange.invite_token)
      end

      it '参加済みであることが分かる' do
        expect(response.body).to include('すでに参加しています')
      end

      it '参加のボタンを出さない' do
        expect(response.body).not_to include('参加する')
      end
    end

    # 参加できるのは登録期間の締切まで。判定はサーバーが受けた時刻で行い、
    # 可否の条件は Exchange::WRITABLE_PHASES に集約する
    describe '参加を受け付ける期間' do
      it '準備中でも参加できる' do
        travel_to '2026-08-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('参加する')
        end
      end

      # 各期間は終了時刻を含まない。締切ちょうどはもう登録期間の外になる
      it '登録の締切ちょうどからは参加できない' do
        travel_to '2026-08-24T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response.body).to include('参加を受け付ける期間は終わりました')
          expect(response.body).not_to include('参加する')
        end
      end

      it '締切を過ぎていても交換会の概要は見える' do
        travel_to '2026-09-01T10:00:00+09:00' do
          get invitation_path(exchange.invite_token)

          expect(response).to have_http_status(:ok)
          expect(response.body).to include('夏の交換会')
        end
      end
    end

    # 招待URLを知っているだけの人が開く画面なので、参加者向けの情報を一切載せない。
    # とくにギフトコードは、一度見えたら取り消せない
    describe '載せない情報' do
      it '本の情報とギフトコードが含まれない' do
        book = create(:book, title: '吾輩は猫である', gift_code: 'GIFTCODE12345678',
                             participation: create(:participation, exchange:))

        get invitation_path(exchange.invite_token)

        expect(response.body).not_to include(book.title)
        expect(response.body).not_to include(book.gift_code)
      end
    end
  end
end
