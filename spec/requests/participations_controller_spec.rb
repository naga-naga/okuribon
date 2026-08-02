# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ParticipationsController do
  let!(:exchange) do
    create(:exchange,
           name: '夏の交換会',
           registration_starts_at: '2026-08-01T00:00:00+09:00'.in_time_zone,
           registration_ends_at: '2026-08-08T00:00:00+09:00'.in_time_zone,
           wish_ends_at: '2026-08-15T00:00:00+09:00'.in_time_zone)
  end
  let!(:user) { create(:user) }

  # 登録期間の中。参加できる時刻の既定として使う
  let!(:registration) { '2026-08-04T00:00:00+09:00'.in_time_zone }

  def join(token = exchange.invite_token)
    post invitation_participation_path(token)
  end

  describe '#create' do
    describe 'ログイン済みのとき' do
      before { log_in_as(user) }

      it '参加して招待URLへ戻る' do
        travel_to(registration) { join }

        expect(exchange.participant?(user)).to be(true)
        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end

      it '参加したことが伝わる' do
        travel_to(registration) { join }
        follow_redirect!

        expect(response.body).to include('参加しました')
      end

      # 二重送信や、戻るボタンからの再送信で参加が増えないこと
      it '二度送っても参加は1つのまま' do
        travel_to(registration) do
          join
          join
        end

        expect(exchange.participations.count).to eq(1)
      end

      # 存在しない交換会と、招待されていない交換会を見分けられないようにする
      it '無効なトークンでは参加できない' do
        travel_to(registration) { join('deadbeefdeadbeef') }

        expect(response).to have_http_status(:not_found)
        expect(user.participations).to be_empty
      end

      # 可否はサーバーが受けた時刻で判定する。締切ちょうどはもう登録期間の外
      it '登録の締切ちょうどからは参加できない' do
        travel_to('2026-08-08T00:00:00+09:00') { join }

        expect(response).to have_http_status(:conflict)
        expect(exchange.participations).to be_empty
      end

      it '準備中でも参加できる' do
        travel_to('2026-07-25T00:00:00+09:00') { join }

        expect(exchange.participant?(user)).to be(true)
      end
    end

    # 認証開始は POST に限るため、この経路からそのまま OAuth へは渡せない。
    # 参加の意図だけを保存してログイン画面へ送り、戻ってきたところで参加を確定させる
    describe '未ログインのとき' do
      it 'ログイン画面へ送り、まだ参加させない' do
        travel_to(registration) { join }

        expect(response).to redirect_to(login_path)
        expect(exchange.participations).to be_empty
      end

      it 'ログインを終えると参加が確定し、招待URLへ戻る' do
        travel_to(registration) do
          join
          log_in_as(user)
        end

        expect(exchange.participant?(user)).to be(true)
        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end

      it '参加したことが伝わる' do
        travel_to(registration) do
          join
          log_in_as(user)
        end
        follow_redirect!

        expect(response.body).to include('参加しました')
      end

      # 押していない人を参加させない。招待URLを開いただけで立ち去った人が、
      # 後日どこかでログインした拍子に参加させられてしまわないこと
      it '押さずにログインしただけでは参加しない' do
        travel_to(registration) do
          get invitation_path(exchange.invite_token)
          log_in_as(user)
        end

        expect(exchange.participations).to be_empty
      end

      # 保存した意図を残すと、次のログインで身に覚えのない参加が作られる
      it '一度使った参加の意図は残らない' do
        travel_to(registration) do
          join
          log_in_as(user)
          log_out

          expect { log_in_as(user) }.not_to change(Participation, :count)
          expect(response).to redirect_to(root_path)
        end
      end

      # Google の同意画面にいる間に締切をまたぐことがある。
      # ここで参加ごとログインを失敗させると、利用者には何が起きたのか分からない
      it '同意の最中に締切を過ぎたら、参加は見送りログインだけ成立させる' do
        travel_to(registration) { join }
        travel_to('2026-08-08T00:00:00+09:00') do
          log_in_as(user)

          expect(session[:user_id]).to eq(user.id)
          expect(exchange.participations).to be_empty

          follow_redirect!
          expect(response.body).to include('参加を受け付ける期間は終わりました')
        end
      end
    end
  end
end
