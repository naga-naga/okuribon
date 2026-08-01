# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OAuth のコールバック' do
  let!(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      info: { name: '送本 太郎', image: 'https://example.com/a.png' }
    )
  end

  before { OmniAuth.config.mock_auth[:google_oauth2] = auth }

  it '認証に成功すると利用者ができる' do
    expect { get '/auth/google_oauth2/callback' }.to change(User, :count).by(1)

    expect(User.last).to have_attributes(
      provider: 'google_oauth2',
      uid: '100000000000000000001',
      display_name: '送本 太郎',
      avatar_url: 'https://example.com/a.png'
    )
  end

  # 再ログインのたびに増えると、参加も本も別人のものとして分かれてしまう
  it '同じ人が再ログインしても利用者は増えない' do
    get '/auth/google_oauth2/callback'

    expect { get '/auth/google_oauth2/callback' }.not_to change(User, :count)
  end

  it '認証後は画面へ戻す' do
    get '/auth/google_oauth2/callback'

    expect(response).to have_http_status(:redirect)
  end
end
