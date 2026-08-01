# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SessionsController do
  let!(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      info: { name: '贈本 太郎', image: 'https://example.com/a.png' }
    )
  end

  before { OmniAuth.config.mock_auth[:google_oauth2] = auth }

  describe '#new' do
    it 'root からも開ける' do
      get '/'

      expect(response).to have_http_status(:ok)
    end

    # 認証開始は POST に限る。リンクで置くと GET になり、外部サイトから踏ませられる
    it '認証開始への POST を置く' do
      get '/login'

      expect(response.body).to include('action="/auth/google_oauth2"')
      expect(response.body).to include('method="post"')
    end

    it 'ログイン済みなら表示名とログアウトを出す' do
      get '/auth/google_oauth2/callback'

      get '/login'

      expect(response.body).to include('贈本 太郎')
      expect(response.body).to include('ログアウト')
    end
  end

  describe '#create' do
    it '認証に成功すると利用者ができる' do
      expect { get '/auth/google_oauth2/callback' }.to change(User, :count).by(1)

      expect(User.last).to have_attributes(
        provider: 'google_oauth2',
        uid: '100000000000000000001',
        display_name: '贈本 太郎',
        avatar_url: 'https://example.com/a.png'
      )
    end

    # 再ログインのたびに増えると、参加も本も別人のものとして分かれてしまう
    it '同じ人が再ログインしても利用者は増えない' do
      get '/auth/google_oauth2/callback'

      expect { get '/auth/google_oauth2/callback' }.not_to change(User, :count)
    end

    it '認証に成功するとログイン状態になる' do
      get '/auth/google_oauth2/callback'

      expect(session[:user_id]).to eq(User.last.id)
    end

    it '認証後は画面へ戻す' do
      get '/auth/google_oauth2/callback'

      expect(response).to have_http_status(:redirect)
    end
  end

  describe '#destroy' do
    before { get '/auth/google_oauth2/callback' }

    it 'セッションが破棄される' do
      delete '/logout'

      expect(session[:user_id]).to be_nil
    end

    it 'ログイン画面へ戻す' do
      delete '/logout'

      expect(response).to redirect_to(login_path)
    end
  end
end
