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

  def withdraw(token = exchange.invite_token)
    delete invitation_participation_path(token)
  end

  describe '#create' do
    describe 'ログイン済みのとき' do
      before { log_in_as(user) }

      # 招待URL着地画面は未参加の人のための画面。参加が済んだらトップへ渡す
      it '参加して交換会トップへ移る' do
        travel_to(registration) { join }

        expect(exchange.participant?(user)).to be(true)
        expect(response).to redirect_to(exchange_path(exchange))
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

        expect(exchange.participations.where(user:).count).to eq(1)
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
        expect(exchange.participant?(user)).to be(false)
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
        expect(exchange.participant?(user)).to be(false)
      end

      # ログインを挟んでも行き着く先は同じ。経路によって着地が変わると、
      # 参加できたのかどうかを画面から読み取れない
      it 'ログインを終えると参加が確定し、交換会トップへ移る' do
        travel_to(registration) do
          join
          log_in_as(user)
        end

        expect(exchange.participant?(user)).to be(true)
        expect(response).to redirect_to(exchange_path(exchange))
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

        expect(exchange.participant?(user)).to be(false)
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
          expect(exchange.participant?(user)).to be(false)

          follow_redirect!
          expect(response.body).to include('この交換会には参加できません')
        end
      end
    end
  end

  describe '#destroy' do
    describe 'ログイン済みのとき' do
      before { log_in_as(user) }

      it '辞退して招待URLへ戻る' do
        travel_to(registration) do
          join
          withdraw
        end

        expect(exchange.participant?(user)).to be(false)
        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end

      it '辞退したことが伝わる' do
        travel_to(registration) do
          join
          withdraw
        end
        follow_redirect!

        expect(response.body).to include('参加を取り消しました')
      end

      # 抜けた人の本が残ると、誰も受け取れない本として一覧に並び続ける
      it '登録した本も一緒に取り消される' do
        travel_to(registration) do
          participation = exchange.join!(user, at: registration)
          create(:book, participation:)

          expect { withdraw }.to change(Book, :count).by(-1)
        end
      end

      # 可否はサーバーが受けた時刻で判定する。締切ちょうどはもう登録期間の外。
      # ここで抜けられると取得枠の計算が壊れる
      it '登録の締切ちょうどからは辞退できない' do
        travel_to(registration) { join }
        travel_to('2026-08-08T00:00:00+09:00') { withdraw }

        expect(response).to have_http_status(:conflict)
        expect(exchange.participant?(user)).to be(true)
      end

      it '準備中でも辞退できる' do
        travel_to('2026-07-25T00:00:00+09:00') do
          join
          withdraw
        end

        expect(exchange.participant?(user)).to be(false)
      end

      # 二重送信や、戻るボタンからの再送信で 500 にしない
      it '二度送っても落ちない' do
        travel_to(registration) do
          join
          withdraw
          withdraw
        end

        expect(response).to redirect_to(invitation_path(exchange.invite_token))
      end

      # 存在しない交換会と、招待されていない交換会を見分けられないようにする
      it '無効なトークンでは辞退できない' do
        travel_to(registration) do
          join
          withdraw('deadbeefdeadbeef')
        end

        expect(response).to have_http_status(:not_found)
        expect(exchange.participant?(user)).to be(true)
      end

      # 辞退したあと考え直すことはある。登録期間のうちなら戻れる
      it '辞退したあとに参加し直せる' do
        travel_to(registration) do
          join
          withdraw
          join
        end

        expect(exchange.participant?(user)).to be(true)
      end

      it '辞退したあと締切を過ぎると参加し直せない' do
        travel_to(registration) do
          join
          withdraw
        end
        travel_to('2026-08-08T00:00:00+09:00') { join }

        expect(response).to have_http_status(:conflict)
        expect(exchange.participant?(user)).to be(false)
      end
    end

    # ボタンを出していなくても、このエンドポイントを直接叩けば届く。拒否はサーバー側で行う
    describe '主催者のとき' do
      before do
        exchange.join!(exchange.owner, at: registration)
        log_in_as(exchange.owner)
      end

      # フェーズも認可も正しく、役割だけが許していない。409 とは別の理由になる
      it '辞退できない' do
        travel_to(registration) { withdraw }

        expect(response).to have_http_status(:forbidden)
        expect(exchange.participant?(exchange.owner)).to be(true)
      end

      it '理由が分かる' do
        travel_to(registration) { withdraw }

        expect(response.body).to include('主催者は交換会から抜けられません')
      end
    end

    # 参加していない人に取り消すものは無い。参加のルートと違い、
    # ログインを挟んで続きをやる意味も無いので、意図は保存しない
    it '未ログインならログイン画面へ送る' do
      travel_to(registration) { withdraw }

      expect(response).to redirect_to(login_path)
    end
  end
end
