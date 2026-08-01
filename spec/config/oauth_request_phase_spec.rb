# frozen_string_literal: true

require 'rails_helper'

# 認証の開始を GET で踏めると、外部サイトに置いた画像やリンクだけで認証をやり直させられる。
# POST に限り、かつ CSRF トークンを要求する。
#
# 固定しているのは OmniAuth のミドルウェアの設定で、アプリのコードは通らない。
# spec/config なので type は推論されない。HTTP の口を叩くため明示する
RSpec.describe 'OAuth の認証開始', type: :request do
  let!(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      info: { name: '贈本 太郎', image: 'https://example.com/a.png' }
    )
  end

  before { OmniAuth.config.mock_auth[:google_oauth2] = auth }

  it 'POST なら認証を開始する' do
    post '/auth/google_oauth2'

    expect(response).to redirect_to('/auth/google_oauth2/callback')
  end

  # 認証開始のパスに Rails 側の経路は無い。POST を横取りするのは OmniAuth の
  # ミドルウェアだけなので、POST 以外は素通りして経路が無いまま終わる
  it 'GET では認証を開始しない' do
    get '/auth/google_oauth2'

    expect(response).to have_http_status(:not_found)
  end

  describe 'CSRF トークン' do
    # テストモードでは検証そのものが走らない。ここだけ実物の経路を通す
    around do |example|
      OmniAuth.config.test_mode = false
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it 'トークンの無い POST はプロバイダへ送らない' do
      post '/auth/google_oauth2'

      expect(response.headers['Location']).not_to include('accounts.google.com')
      expect(response.headers['Location']).to include('InvalidAuthenticityToken')
    end
  end
end
