# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ParticipantsController do
  let!(:owner) { create(:user) }
  let!(:exchange) do
    create(:exchange,
           owner:,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end

  # 除外できる時刻の既定。参加できる期間と一致する
  let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

  let!(:participant) { create(:user) }
  let!(:participation) { create(:participation, exchange:, user: participant) }

  # 登録の締切ちょうど。期間は終了時刻を含まないので、ここはもう締切後にあたる
  def deadline
    '2026-08-08T00:00:00+09:00'.in_time_zone
  end

  # 主催者の参加は factory が作る
  def owner_participation
    exchange.participations.find_by!(user: owner)
  end

  def exclude(target = participation)
    delete exchange_management_participant_path(exchange, target)
  end

  describe '#destroy' do
    context '主催者のとき' do
      before { log_in_as(owner) }

      it '登録期間中なら参加者を外せる' do
        travel_to(registration) { exclude }

        expect(exchange.participant?(participant)).to be(false)
      end

      # 抜けた人の本が残ると、誰も受け取れない本として一覧に並び続ける
      it '外した人が登録した本もあわせて消える' do
        create(:book, participation:)

        expect { travel_to(registration) { exclude } }.to change(Book, :count).by(-1)
      end

      it '他の参加者は残る' do
        another = create(:participation, exchange:)

        travel_to(registration) { exclude }

        expect(exchange.participant?(another.user)).to be(true)
      end

      # 参加できるのは準備中から。抜けられる期間も同じ表から引く
      it '準備中でも外せる' do
        travel_to('2026-07-25T00:00:00+09:00') { exclude }

        expect(exchange.participant?(participant)).to be(false)
      end

      it '管理画面へ戻り、外したことが伝わる' do
        travel_to(registration) do
          exclude

          expect(response).to redirect_to(exchange_management_path(exchange))
          follow_redirect!
        end

        expect(response.body).to include("#{participant.display_name} さんを交換会から外しました")
      end

      # 参加の記録は残さず消す。締切前なら本人が入り直せる
      it '外された人は、登録期間のうちなら参加し直せる' do
        travel_to(registration) do
          exclude

          expect { exchange.join!(participant, at: registration) }
            .to change { exchange.participant?(participant) }.from(false).to(true)
        end
      end

      # 希望提出期間に入ってから抜けられると取得枠の計算が壊れる。
      # クライアントが何を送ってきても、判定はサーバーが受けた時刻で行う
      it '登録の締切を過ぎていれば 409 で拒否し、参加は残る' do
        travel_to(deadline) { exclude }

        expect(response).to have_http_status(:conflict)
        expect(exchange.participant?(participant)).to be(true)
      end

      it '拒否の応答に、いまのフェーズとできなかった操作が出る' do
        travel_to(deadline) { exclude }

        expect(response.body).to include('希望提出期間', '参加の変更')
      end

      # 主催者は必ず参加者を兼ねる。待てば通るわけではないので
      # 409 ではなく 403 で断る
      it '自分自身は外せず、403 になる' do
        travel_to(registration) { delete exchange_management_participant_path(exchange, owner_participation) }

        expect(response).to have_http_status(:forbidden)
        expect(exchange.participant?(owner)).to be(true)
      end

      # 判定は役割を先に見る。フェーズを先に見ると、締切後に押したときだけ理由が入れ替わる
      it '締切後に自分自身を外そうとしても 403 のままになる' do
        travel_to(deadline) { delete exchange_management_participant_path(exchange, owner_participation) }

        expect(response).to have_http_status(:forbidden)
      end

      # id は交換会の下から引く。番号を数えるだけで他の交換会の参加を消せてはいけない
      it '他の交換会の参加を指定しても 404 になり、その参加は残る' do
        another = create(:participation)

        travel_to(registration) { delete exchange_management_participant_path(exchange, another) }

        expect(response).to have_http_status(:not_found)
        expect(another.exchange.participant?(another.user)).to be(true)
      end
    end

    # 403 だと、招待されていない交換会が実在することを URL を試すだけで
    # 確かめられてしまう
    it '参加しているだけの人には 404 を返し、参加も残る' do
      log_in_as(participant)

      travel_to(registration) { exclude }

      expect(response).to have_http_status(:not_found)
      expect(exchange.participant?(participant)).to be(true)
    end

    it '参加していない人には 404 を返し、参加も残る' do
      log_in_as(create(:user))

      travel_to(registration) { exclude }

      expect(response).to have_http_status(:not_found)
      expect(exchange.participant?(participant)).to be(true)
    end

    it '未ログインならログイン画面へ送り、参加も残る' do
      travel_to(registration) { exclude }

      expect(response).to redirect_to(login_path)
      expect(exchange.participant?(participant)).to be(true)
    end

    # ログインを挟むぶん、主催者以外の 404 とは応答が変わる。実在する交換会だけが
    # ログイン画面へ、存在しない id が 404 へ分かれると、未ログインのまま
    # id を試すだけで実在を確かめられてしまう
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      travel_to(registration) do
        exclude
        existing = [response.status, response.headers['Location']]

        delete exchange_management_participant_path(Exchange.maximum(:id) + 1, participation)

        expect([response.status, response.headers['Location']]).to eq(existing)
      end
    end
  end
end
