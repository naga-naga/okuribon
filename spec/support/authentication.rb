# frozen_string_literal: true

# spec でログイン状態を作る。
# セッションを直に書けないため、実際の OAuth コールバックを通す。
# 認証情報は利用者のレコードから組み立てるので、from_omniauth は
# 新しく作らずにその利用者を引き当てる
module AuthenticationHelper
  private

  def mock_omniauth_as(user)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: user.provider,
      uid: user.uid,
      info: { name: user.display_name, image: user.avatar_url }
    )
  end
end

module RequestAuthenticationHelper
  include AuthenticationHelper

  def log_in_as(user)
    mock_omniauth_as(user)

    get oauth_callback_path
  end

  def log_out
    delete logout_path
  end
end

module SystemAuthenticationHelper
  include AuthenticationHelper

  def log_in_as(user)
    mock_omniauth_as(user)

    visit oauth_callback_path
  end
end

RSpec.configure do |config|
  config.include RequestAuthenticationHelper, type: :request
  config.include SystemAuthenticationHelper, type: :system
end
