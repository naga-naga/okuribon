# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InviteTokensController do
  # 下の exchange の日程に対して、各フェーズに落ちる時刻。
  # 締切は JST で決まるので、オフセットまで書いて日跨ぎの解釈を環境に委ねない
  let!(:phase_times) do
    { preparing: '2026-07-25T00:00:00+09:00', registration: '2026-08-04T00:00:00+09:00',
      wish: '2026-08-11T00:00:00+09:00', awaiting_matching: '2026-08-20T00:00:00+09:00',
      published: '2026-08-20T00:00:00+09:00' }.transform_values(&:in_time_zone).freeze
  end

  let!(:owner) { create(:user) }
  let!(:exchange) do
    create(:exchange,
           owner:,
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end

  # 登録期間の中。まだ人を招ける時刻の既定として使う
  let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

  def reissue(target = exchange)
    patch exchange_management_invite_token_path(target)
  end

  describe '#update' do
    context '主催者のとき' do
      before { log_in_as(owner) }

      it '招待トークンが別のものに変わる' do
        before_token = exchange.invite_token

        travel_to(registration) { reissue }

        expect(exchange.reload.invite_token).not_to eq(before_token)
      end

      # 配り直したい理由はたいてい「渡してはいけない相手に渡った」なので、
      # 古いURLが開けたままでは再発行の意味が無い
      it '古い招待URLは開けなくなる' do
        old_token = exchange.invite_token

        travel_to(registration) do
          reissue

          get invitation_path(old_token)
        end

        expect(response).to have_http_status(:not_found)
      end

      it '新しい招待URLで着地画面が開ける' do
        travel_to(registration) do
          reissue

          get invitation_path(exchange.reload.invite_token)
        end

        expect(response).to have_http_status(:ok)
      end

      it '管理画面へ戻り、古いURLが使えなくなったことが伝わる' do
        travel_to(registration) do
          reissue

          expect(response).to redirect_to(exchange_management_path(exchange))
          follow_redirect!
        end

        expect(response.body).to include('招待URLを再発行しました')
      end

      # 参加は user と交換会で結ばれていて招待トークンを見ない。
      # ここが落ちるなら、配り直しのたびに参加者を追い出していることになる
      it '既存の参加者は影響を受けない' do
        participant = create(:user)
        create(:participation, exchange:, user: participant)

        travel_to(registration) { reissue }

        expect(exchange.participant?(participant)).to be(true)
        expect(exchange.participations.count).to eq(2)
      end

      # 締切後に配り直しても、参加を断るのは着地画面の仕事。
      # 管理画面はどのフェーズでも開ける約束なので、ここもフェーズで閉じない
      it 'どのフェーズでも再発行できる' do
        Exchange::PHASES.each do |phase|
          at = phase_times.fetch(phase)
          # 結果公開はフェーズ導出の入口が違う。日時ではなく実行済みかどうかで決まる
          exchange.update!(matched_at: phase == :published ? at : nil)
          before_token = exchange.invite_token

          travel_to(at) { reissue }

          expect(exchange.phase(at:)).to eq(phase)
          expect(exchange.reload.invite_token).not_to eq(before_token), "#{phase} で再発行できなかった"
        end
      end
    end

    it '参加しているだけの人には 404 を返し、トークンも変わらない' do
      participant = create(:user)
      create(:participation, exchange:, user: participant)
      log_in_as(participant)
      before_token = exchange.invite_token

      travel_to(registration) { reissue }

      expect(response).to have_http_status(:not_found)
      expect(exchange.reload.invite_token).to eq(before_token)
    end

    it '参加していない人には 404 を返し、トークンも変わらない' do
      log_in_as(create(:user))
      before_token = exchange.invite_token

      travel_to(registration) { reissue }

      expect(response).to have_http_status(:not_found)
      expect(exchange.reload.invite_token).to eq(before_token)
    end

    it '未ログインならログイン画面へ送り、トークンも変わらない' do
      before_token = exchange.invite_token

      travel_to(registration) { reissue }

      expect(response).to redirect_to(login_path)
      expect(exchange.reload.invite_token).to eq(before_token)
    end

    # require_login が Exchange を引く前に返すので応答が揃う
    it '未ログインなら、実在しない交換会でも応答が変わらない' do
      travel_to(registration) do
        reissue
        existing = [response.status, response.headers['Location']]

        patch exchange_management_invite_token_path(Exchange.maximum(:id) + 1)

        expect([response.status, response.headers['Location']]).to eq(existing)
      end
    end
  end
end
